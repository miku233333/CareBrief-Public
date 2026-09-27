import CareBriefAppSupport
import CareBriefCore
import CryptoKit
import Foundation

enum CareBriefSHA256 {
  static func hexDigest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  static func sourceDocumentHash(_ text: String) -> String {
    hexDigest(Data(text.utf8))
  }

  static func markerURL(for request: ActionExportRequest) -> URL? {
    URL(
      string:
        "carebrief://export/v1/\(request.destination.rawValue)/\(hexDigest(request.markerCanonicalPayload))"
    )
  }
}

@MainActor
final class EventKitActionExporter: ActionExporting {
  private enum FullAccessStatus {
    case notDetermined
    case restricted
    case denied
    case fullAccess
    case writeOnly
    case unknown
  }

  private enum DuplicateLookup {
    case none
    case one
    case ambiguous
  }

  private let gateway: any EventKitStoreGateway
  private let calendar: Calendar
  private var inFlightMarkers: Set<String> = []
  private var issuedReceipts: [UUID: ExportReceipt] = [:]
  private var consumedReceiptKeys: Set<String> = []

  init(
    gateway: any EventKitStoreGateway = SystemEventKitStoreGateway(),
    calendar: Calendar = CareBriefCalendar.localGregorian()
  ) {
    self.gateway = gateway
    self.calendar = CareBriefCalendar.localGregorian(timeZone: calendar.timeZone)
  }

  func export(_ requests: [ActionExportRequest]) async -> ActionExportBatchResult {
    let operationID = UUID()
    let needsEvents = requests.contains(where: { $0.destination == .calendar })
    let needsReminders = requests.contains(where: { $0.destination == .reminder })
    let eventAccessFailure = needsEvents ? await ensureFullAccess(to: .events) : nil
    let reminderAccessFailure =
      needsReminders
      ? await ensureFullAccess(to: .reminders) : nil
    var results: [ActionExportItemResult] = []

    for request in requests {
      if request.destination == .calendar, let eventAccessFailure {
        results.append(
          ActionExportItemResult(
            actionID: request.actionID,
            outcome: .failed(eventAccessFailure)
          )
        )
        continue
      }
      if request.destination == .reminder, let reminderAccessFailure {
        results.append(
          ActionExportItemResult(
            actionID: request.actionID,
            outcome: .failed(reminderAccessFailure)
          )
        )
        continue
      }
      results.append(await exportOne(request))
    }

    let batch = ActionExportBatchResult(operationID: operationID, results: results)
    if let receipt = batch.receipt {
      issuedReceipts[operationID] = receipt
    }
    return batch
  }

  func undo(_ receipt: ExportReceipt) async -> ActionUndoBatchResult {
    guard let issuedReceipt = issuedReceipts[receipt.operationID], issuedReceipt == receipt else {
      let allPreviouslyConsumed =
        !receipt.items.isEmpty
        && receipt.items.allSatisfy {
          consumedReceiptKeys.contains(
            receiptKey(operationID: receipt.operationID, item: $0)
          )
        }
      let outcome: ActionUndoItemOutcome =
        allPreviouslyConsumed
        ? .alreadyRemoved : .failed(.invalidReceipt)
      return ActionUndoBatchResult(
        operationID: receipt.operationID,
        results: receipt.items.map {
          ActionUndoItemResult(actionID: $0.actionID, outcome: outcome)
        }
      )
    }

    var results: [ActionUndoItemResult] = []
    for item in receipt.items {
      let key = receiptKey(operationID: receipt.operationID, item: item)
      if consumedReceiptKeys.contains(key) {
        results.append(ActionUndoItemResult(actionID: item.actionID, outcome: .alreadyRemoved))
        continue
      }
      guard let identifier = item.calendarItemIdentifier, !identifier.isEmpty else {
        results.append(
          ActionUndoItemResult(actionID: item.actionID, outcome: .failed(.invalidReceipt))
        )
        continue
      }
      if let accessFailure = await ensureFullAccess(
        to: item.destination == .calendar ? .events : .reminders
      ) {
        results.append(
          ActionUndoItemResult(actionID: item.actionID, outcome: .failed(accessFailure))
        )
        continue
      }

      let gatewayResult = await gateway.removeItem(
        identifier: identifier,
        destination: item.destination,
        expectedMarkerURLString: item.markerURLString
      )
      let outcome: ActionUndoItemOutcome
      switch gatewayResult {
      case .removed:
        outcome = .removed
        consumedReceiptKeys.insert(key)
      case .missing:
        outcome = .failed(.itemNotFound)
      case .markerMismatch, .typeMismatch:
        outcome = .failed(.itemChanged)
      case .failed:
        outcome = .failed(.removeFailed)
      }
      results.append(ActionUndoItemResult(actionID: item.actionID, outcome: outcome))
    }

    if issuedReceipt.items.allSatisfy({
      consumedReceiptKeys.contains(receiptKey(operationID: receipt.operationID, item: $0))
    }) {
      issuedReceipts.removeValue(forKey: receipt.operationID)
    }
    return ActionUndoBatchResult(operationID: receipt.operationID, results: results)
  }

  private func exportOne(_ request: ActionExportRequest) async -> ActionExportItemResult {
    guard let markerURL = CareBriefSHA256.markerURL(for: request) else {
      return ActionExportItemResult(
        actionID: request.actionID,
        outcome: .failed(.saveFailed)
      )
    }
    let marker = markerURL.absoluteString
    guard !inFlightMarkers.contains(marker) else {
      return ActionExportItemResult(
        actionID: request.actionID,
        outcome: .failed(.alreadyInProgress)
      )
    }
    inFlightMarkers.insert(marker)
    defer { inFlightMarkers.remove(marker) }

    do {
      switch try await duplicateLookup(for: request, markerURL: markerURL) {
      case .one:
        return ActionExportItemResult(actionID: request.actionID, outcome: .alreadyAdded)
      case .ambiguous:
        return ActionExportItemResult(
          actionID: request.actionID,
          outcome: .failed(.ambiguousDuplicate)
        )
      case .none:
        let snapshot = try await gateway.create(
          request: request,
          markerURL: markerURL,
          calendar: calendar
        )
        guard snapshot.destination == request.destination,
          snapshot.markerURLString == marker,
          let identifier = snapshot.identifier?.trimmingCharacters(in: .whitespacesAndNewlines),
          !identifier.isEmpty
        else {
          throw ActionExportFailure.saveFailed
        }
        let receipt = ExportReceiptItem(
          actionID: request.actionID,
          destination: request.destination,
          calendarItemIdentifier: identifier,
          markerURLString: marker,
          dateTime: request.dateTime
        )
        return ActionExportItemResult(actionID: request.actionID, outcome: .created(receipt))
      }
    } catch let failure as ActionExportFailure {
      return ActionExportItemResult(actionID: request.actionID, outcome: .failed(failure))
    } catch {
      return ActionExportItemResult(actionID: request.actionID, outcome: .failed(.saveFailed))
    }
  }

  private func duplicateLookup(
    for request: ActionExportRequest,
    markerURL: URL
  ) async throws -> DuplicateLookup {
    let candidates: [EventKitItemSnapshot]
    switch request.destination {
    case .calendar:
      guard let range = eventSearchRange(for: request.dateTime) else {
        throw ActionExportFailure.invalidDate
      }
      candidates = try await gateway.matchingItems(
        destination: .calendar,
        startDate: range.start,
        endDate: range.end,
        expectedMarkerURLString: markerURL.absoluteString
      )
    case .reminder:
      candidates = try await gateway.matchingItems(
        destination: .reminder,
        startDate: nil,
        endDate: nil,
        expectedMarkerURLString: markerURL.absoluteString
      )
    case .skip:
      return .none
    }

    let matches = candidates.filter {
      $0.destination == request.destination
        && $0.markerURLString == markerURL.absoluteString
    }
    switch matches.count {
    case 0: return .none
    case 1: return .one
    default: return .ambiguous
    }
  }

  private func ensureFullAccess(to entity: EventKitEntity) async -> ActionExportFailure? {
    let initial = await fullAccessStatus(for: entity)
    switch initial {
    case .fullAccess:
      return nil
    case .restricted:
      return .permissionRestricted
    case .denied:
      return .permissionDenied
    case .notDetermined, .writeOnly, .unknown:
      break
    }

    do {
      let granted: Bool
      if #available(iOS 17.0, *) {
        granted = try await gateway.requestFullAccess(to: entity)
      } else {
        granted = try await gateway.requestLegacyAccess(to: entity)
      }
      guard granted else {
        return initial == .writeOnly ? .fullAccessRequired : .permissionDenied
      }
    } catch {
      return initial == .writeOnly ? .fullAccessRequired : .permissionDenied
    }

    switch await fullAccessStatus(for: entity) {
    case .fullAccess:
      return nil
    case .restricted:
      return .permissionRestricted
    case .writeOnly:
      return .fullAccessRequired
    case .notDetermined, .denied, .unknown:
      return .permissionDenied
    }
  }

  private func fullAccessStatus(for entity: EventKitEntity) async -> FullAccessStatus {
    switch await gateway.authorizationStatusRawValue(for: entity) {
    case 0: return .notDetermined
    case 1: return .restricted
    case 2: return .denied
    case 3: return .fullAccess
    case 4: return .writeOnly
    default: return .unknown
    }
  }

  private func eventSearchRange(
    for dateTime: ActionDateTime?
  ) -> (start: Date, end: Date)? {
    guard
      let date = EventKitDateResolver.localDate(
        from: dateTime,
        calendar: calendar
      )
    else {
      return nil
    }
    let day = calendar.startOfDay(for: date)
    guard let start = calendar.date(byAdding: .day, value: -1, to: day),
      let end = calendar.date(byAdding: .day, value: 2, to: day)
    else {
      return nil
    }
    return (start, end)
  }

  private func receiptKey(operationID: UUID, item: ExportReceiptItem) -> String {
    [operationID.uuidString, item.actionID, item.destination.rawValue, item.markerURLString]
      .joined(separator: "|")
  }
}

import CareBriefAppSupport
import CareBriefCore
import Foundation
import Testing

@testable import CareBrief

@MainActor
@Suite struct EventKitActionExporterTests {
  @Test func requestsFullAccessOnlyForDestinationsActuallyUsed() async throws {
    let gateway = FakeEventKitStoreGateway(
      statuses: [.events: 0, .reminders: 0]
    )
    let exporter = EventKitActionExporter(gateway: gateway)

    let result = await exporter.export([makeRequest(id: "event", destination: .calendar)])
    let state = await gateway.state()

    #expect(result.results.first?.outcome.isCreated == true)
    #expect(state.fullAccessRequests == [.events])
    #expect(state.createActionIDs == ["event"])

    let bothGateway = FakeEventKitStoreGateway(
      statuses: [.events: 0, .reminders: 0]
    )
    let bothExporter = EventKitActionExporter(gateway: bothGateway)
    _ = await bothExporter.export([
      makeRequest(id: "event", destination: .calendar),
      makeRequest(id: "reminder", destination: .reminder, dateTime: nil),
    ])
    #expect(await bothGateway.state().fullAccessRequests == [.events, .reminders])
  }

  @Test func deniedRestrictedAndWriteOnlyStatusesMapToSafeFailures() async {
    let deniedGateway = FakeEventKitStoreGateway(statuses: [.events: 2])
    let deniedExporter = EventKitActionExporter(gateway: deniedGateway)
    let denied = await deniedExporter.export([
      makeRequest(id: "denied", destination: .calendar)
    ])
    #expect(denied.results.first?.outcome == .failed(.permissionDenied))
    #expect(await deniedGateway.state().fullAccessRequests.isEmpty)

    let restrictedGateway = FakeEventKitStoreGateway(statuses: [.events: 1])
    let restrictedExporter = EventKitActionExporter(gateway: restrictedGateway)
    let restricted = await restrictedExporter.export([
      makeRequest(id: "restricted", destination: .calendar)
    ])
    #expect(restricted.results.first?.outcome == .failed(.permissionRestricted))
    #expect(await restrictedGateway.state().fullAccessRequests.isEmpty)

    let writeOnlyGateway = FakeEventKitStoreGateway(
      statuses: [.events: 4],
      grantsFullAccess: false
    )
    let writeOnlyExporter = EventKitActionExporter(gateway: writeOnlyGateway)
    let writeOnly = await writeOnlyExporter.export([
      makeRequest(id: "write-only", destination: .calendar)
    ])
    #expect(writeOnly.results.first?.outcome == .failed(.fullAccessRequired))
    #expect(await writeOnlyGateway.state().fullAccessRequests == [.events])
  }

  @Test func missingDefaultCalendarAndReminderListStayItemScoped() async {
    let gateway = FakeEventKitStoreGateway(
      statuses: [.events: 3, .reminders: 3],
      createFailures: [
        "event": .noDefaultCalendar,
        "reminder": .noDefaultReminderList,
      ]
    )
    let exporter = EventKitActionExporter(gateway: gateway)

    let result = await exporter.export([
      makeRequest(id: "event", destination: .calendar),
      makeRequest(id: "reminder", destination: .reminder, dateTime: nil),
    ])

    #expect(result.results[0].outcome == .failed(.noDefaultCalendar))
    #expect(result.results[1].outcome == .failed(.noDefaultReminderList))
    #expect(result.receipt == nil)
    #expect(await gateway.state().createActionIDs == ["event", "reminder"])
  }

  @Test func exactMarkerLookupReportsDuplicateOrAmbiguousWithoutCreating() async throws {
    let request = makeRequest(id: "duplicate", destination: .calendar)
    let marker = try #require(CareBriefSHA256.markerURL(for: request)?.absoluteString)
    let oneGateway = FakeEventKitStoreGateway(
      statuses: [.events: 3],
      matchingItems: [
        .calendar: [
          EventKitItemSnapshot(
            identifier: "existing",
            destination: .calendar,
            markerURLString: marker
          )
        ]
      ]
    )
    let oneExporter = EventKitActionExporter(gateway: oneGateway)

    let duplicate = await oneExporter.export([request])

    #expect(duplicate.results.first?.outcome == .alreadyAdded)
    #expect(await oneGateway.state().createActionIDs.isEmpty)
    #expect(await oneGateway.state().expectedMarkers == [marker])

    let ambiguousGateway = FakeEventKitStoreGateway(
      statuses: [.events: 3],
      matchingItems: [
        .calendar: [
          EventKitItemSnapshot(
            identifier: "first",
            destination: .calendar,
            markerURLString: marker
          ),
          EventKitItemSnapshot(
            identifier: "second",
            destination: .calendar,
            markerURLString: marker
          ),
        ]
      ]
    )
    let ambiguousExporter = EventKitActionExporter(gateway: ambiguousGateway)
    let ambiguous = await ambiguousExporter.export([request])

    #expect(ambiguous.results.first?.outcome == .failed(.ambiguousDuplicate))
    #expect(await ambiguousGateway.state().createActionIDs.isEmpty)
  }

  @Test func reminderLookupFailureDoesNotCreateAnUncheckedDuplicate() async {
    let gateway = FakeEventKitStoreGateway(
      statuses: [.reminders: 3],
      matchingFailureDestinations: [.reminder]
    )
    let exporter = EventKitActionExporter(gateway: gateway)

    let result = await exporter.export([
      makeRequest(id: "reminder", destination: .reminder, dateTime: nil)
    ])

    #expect(result.results.first?.outcome == .failed(.duplicateLookupFailed))
    #expect(result.receipt == nil)
    #expect(await gateway.state().createActionIDs.isEmpty)
  }

  @Test func partialSaveFailureRetainsOnlyTheCreatedItemReceipt() async throws {
    let gateway = FakeEventKitStoreGateway(
      statuses: [.events: 3, .reminders: 3],
      createFailures: ["reminder": .saveFailed]
    )
    let exporter = EventKitActionExporter(gateway: gateway)

    let result = await exporter.export([
      makeRequest(id: "event", destination: .calendar),
      makeRequest(id: "reminder", destination: .reminder, dateTime: nil),
    ])

    #expect(result.results[0].outcome.isCreated)
    #expect(result.results[1].outcome == .failed(.saveFailed))
    #expect(try #require(result.receipt).items.map(\.actionID) == ["event"])
  }

  @Test func creationWithoutStableIdentifierFailsWithoutIssuingReceipt() async {
    let gateway = FakeEventKitStoreGateway(
      statuses: [.events: 3],
      actionIDsWithoutIdentifiers: ["event"]
    )
    let exporter = EventKitActionExporter(gateway: gateway)

    let result = await exporter.export([
      makeRequest(id: "event", destination: .calendar)
    ])

    #expect(result.results.first?.outcome == .failed(.saveFailed))
    #expect(result.receipt == nil)
  }

  @Test func undoRequiresIssuedIdentifierAndExactMarkerAndSupportsRetry() async throws {
    let gateway = FakeEventKitStoreGateway(statuses: [.events: 3])
    let exporter = EventKitActionExporter(gateway: gateway)
    let exported = await exporter.export([
      makeRequest(id: "event", destination: .calendar)
    ])
    let receipt = try #require(exported.receipt)

    await gateway.setRemovalResult(.markerMismatch)
    let mismatch = await exporter.undo(receipt)
    #expect(mismatch.results.first?.outcome == .failed(.itemChanged))

    await gateway.setRemovalResult(.removed)
    let removed = await exporter.undo(receipt)
    #expect(removed.results.first?.outcome == .removed)

    let secondUndo = await exporter.undo(receipt)
    #expect(secondUndo.results.first?.outcome == .alreadyRemoved)
    #expect(await gateway.state().removeCalls.count == 2)
    #expect(
      await gateway.state().removeCalls.last?.expectedMarker == receipt.items[0].markerURLString)
  }

  @Test func removeFailureKeepsIssuedReceiptAvailableForRetry() async throws {
    let gateway = FakeEventKitStoreGateway(statuses: [.events: 3])
    let exporter = EventKitActionExporter(gateway: gateway)
    let exported = await exporter.export([
      makeRequest(id: "event", destination: .calendar)
    ])
    let receipt = try #require(exported.receipt)

    await gateway.setRemovalResult(.failed)
    let failed = await exporter.undo(receipt)
    #expect(failed.results.first?.outcome == .failed(.removeFailed))

    await gateway.setRemovalResult(.removed)
    let retried = await exporter.undo(receipt)

    #expect(retried.results.first?.outcome == .removed)
    #expect(await gateway.state().removeCalls.count == 2)
  }

  @Test func externallyDeletedItemReturnsSafeErrorWithoutConsumingReceipt() async throws {
    let gateway = FakeEventKitStoreGateway(statuses: [.events: 3])
    let exporter = EventKitActionExporter(gateway: gateway)
    let exported = await exporter.export([
      makeRequest(id: "event", destination: .calendar)
    ])
    let receipt = try #require(exported.receipt)
    await gateway.setRemovalResult(.missing)

    let firstAttempt = await exporter.undo(receipt)
    let secondAttempt = await exporter.undo(receipt)

    #expect(firstAttempt.results.first?.outcome == .failed(.itemNotFound))
    #expect(secondAttempt.results.first?.outcome == .failed(.itemNotFound))
    #expect(await gateway.state().removeCalls.count == 2)
  }

  @Test func unresolvedReceiptIdentifierNeverFallsBackToMarkerOnlyDeletion() async throws {
    let gateway = FakeEventKitStoreGateway(statuses: [.events: 3])
    let exporter = EventKitActionExporter(gateway: gateway)
    let exported = await exporter.export([
      makeRequest(id: "event", destination: .calendar)
    ])
    let receipt = try #require(exported.receipt)
    await gateway.setRemovalResult(.missing)

    let result = await exporter.undo(receipt)

    #expect(result.results.first?.outcome == .failed(.itemNotFound))
    #expect(await gateway.state().removeCalls.count == 1)
  }

  @Test func sameMarkerConcurrentExportCreatesAtMostOneItem() async {
    let gateway = FakeEventKitStoreGateway(
      statuses: [.events: 3],
      matchingDelayNanoseconds: 100_000_000
    )
    let exporter = EventKitActionExporter(gateway: gateway)
    let request = makeRequest(id: "event", destination: .calendar)

    async let first = exporter.export([request])
    async let second = exporter.export([request])
    let results = await [first, second]
    let outcomes = results.compactMap { $0.results.first?.outcome }
    let containsCreated = outcomes.map(\.isCreated).contains(true)

    #expect(containsCreated)
    #expect(outcomes.contains(.failed(.alreadyInProgress)))
    #expect(await gateway.state().createActionIDs.count == 1)
  }

  @Test func dateResolverRejectsNonexistentLocalDSTTime() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
    let nonexistent = ActionDateTime(
      year: 2026,
      month: 3,
      day: 8,
      hour: 2,
      minute: 30
    )
    let valid = ActionDateTime(
      year: 2026,
      month: 3,
      day: 8,
      hour: 3,
      minute: 30
    )

    #expect(EventKitDateResolver.localDate(from: nonexistent, calendar: calendar) == nil)
    #expect(EventKitDateResolver.localDate(from: valid, calendar: calendar) != nil)
  }
}

private struct FakeEventKitState: Sendable {
  struct RemoveCall: Sendable {
    let identifier: String
    let destination: ActionExportDestination
    let expectedMarker: String
  }

  let fullAccessRequests: [EventKitEntity]
  let createActionIDs: [String]
  let expectedMarkers: [String]
  let removeCalls: [RemoveCall]
}

private actor FakeEventKitStoreGateway: EventKitStoreGateway {
  private var statuses: [EventKitEntity: Int]
  private let grantsFullAccess: Bool
  private var configuredMatchingItems: [ActionExportDestination: [EventKitItemSnapshot]]
  private let createFailures: [String: ActionExportFailure]
  private let actionIDsWithoutIdentifiers: Set<String>
  private let matchingDelayNanoseconds: UInt64
  private let matchingFailureDestinations: Set<ActionExportDestination>
  private var removalResult: EventKitGatewayRemovalResult = .removed
  private var fullAccessRequests: [EventKitEntity] = []
  private var createActionIDs: [String] = []
  private var expectedMarkers: [String] = []
  private var removeCalls: [FakeEventKitState.RemoveCall] = []

  init(
    statuses: [EventKitEntity: Int] = [:],
    grantsFullAccess: Bool = true,
    matchingItems: [ActionExportDestination: [EventKitItemSnapshot]] = [:],
    createFailures: [String: ActionExportFailure] = [:],
    actionIDsWithoutIdentifiers: Set<String> = [],
    matchingDelayNanoseconds: UInt64 = 0,
    matchingFailureDestinations: Set<ActionExportDestination> = []
  ) {
    self.statuses = statuses
    self.grantsFullAccess = grantsFullAccess
    self.configuredMatchingItems = matchingItems
    self.createFailures = createFailures
    self.actionIDsWithoutIdentifiers = actionIDsWithoutIdentifiers
    self.matchingDelayNanoseconds = matchingDelayNanoseconds
    self.matchingFailureDestinations = matchingFailureDestinations
  }

  func authorizationStatusRawValue(for entity: EventKitEntity) async -> Int {
    statuses[entity] ?? 3
  }

  func requestFullAccess(to entity: EventKitEntity) async throws -> Bool {
    fullAccessRequests.append(entity)
    if grantsFullAccess {
      statuses[entity] = 3
    }
    return grantsFullAccess
  }

  @available(iOS, introduced: 6.0, deprecated: 17.0)
  func requestLegacyAccess(to entity: EventKitEntity) async throws -> Bool {
    fullAccessRequests.append(entity)
    if grantsFullAccess {
      statuses[entity] = 3
    }
    return grantsFullAccess
  }

  func matchingItems(
    destination: ActionExportDestination,
    startDate: Date?,
    endDate: Date?,
    expectedMarkerURLString: String
  ) async throws -> [EventKitItemSnapshot] {
    _ = startDate
    _ = endDate
    expectedMarkers.append(expectedMarkerURLString)
    if matchingDelayNanoseconds > 0 {
      try? await Task.sleep(nanoseconds: matchingDelayNanoseconds)
    }
    if matchingFailureDestinations.contains(destination) {
      throw ActionExportFailure.duplicateLookupFailed
    }
    return configuredMatchingItems[destination] ?? []
  }

  func create(
    request: ActionExportRequest,
    markerURL: URL,
    calendar: Calendar
  ) async throws -> EventKitItemSnapshot {
    _ = calendar
    createActionIDs.append(request.actionID)
    if let failure = createFailures[request.actionID] {
      throw failure
    }
    return EventKitItemSnapshot(
      identifier: actionIDsWithoutIdentifiers.contains(request.actionID)
        ? nil : "\(request.actionID)-identifier",
      destination: request.destination,
      markerURLString: markerURL.absoluteString
    )
  }

  func removeItem(
    identifier: String,
    destination: ActionExportDestination,
    expectedMarkerURLString: String
  ) async -> EventKitGatewayRemovalResult {
    removeCalls.append(
      FakeEventKitState.RemoveCall(
        identifier: identifier,
        destination: destination,
        expectedMarker: expectedMarkerURLString
      )
    )
    return removalResult
  }

  func setRemovalResult(_ result: EventKitGatewayRemovalResult) {
    removalResult = result
  }

  func state() -> FakeEventKitState {
    FakeEventKitState(
      fullAccessRequests: fullAccessRequests,
      createActionIDs: createActionIDs,
      expectedMarkers: expectedMarkers,
      removeCalls: removeCalls
    )
  }
}

private func makeRequest(
  id: String,
  destination: ActionExportDestination,
  dateTime: ActionDateTime? = ActionDateTime(year: 2026, month: 8, day: 15, hour: 9)
) -> ActionExportRequest {
  ActionExportRequest(
    actionID: id,
    destination: destination,
    title: id,
    notes: nil,
    dateTime: dateTime,
    location: nil,
    isAllDay: destination == .calendar && dateTime?.hasTime != true,
    durationMinutes: destination == .calendar && dateTime?.hasTime == true ? 60 : nil,
    markerCanonicalPayload: Data("marker-\(id)-\(destination.rawValue)".utf8)
  )
}

extension ActionExportItemOutcome {
  fileprivate var isCreated: Bool {
    if case .created = self { return true }
    return false
  }
}

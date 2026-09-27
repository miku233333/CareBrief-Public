import CareBriefCore
import Foundation

public enum ActionExportDestination: String, CaseIterable, Equatable, Hashable, Sendable {
  case skip
  case calendar
  case reminder
}

public enum ActionExportDefaults {
  public static func destination(for category: ActionCategory) -> ActionExportDestination {
    switch category {
    case .appointment:
      return .calendar
    case .deadline, .preparation, .requiredItem, .nextStep:
      return .reminder
    case .contact, .location:
      return .skip
    }
  }
}

public struct ActionExportPreviewItem: Equatable, Identifiable, Sendable {
  public var id: String { actionID }

  public let actionID: String
  public let category: ActionCategory
  public let sourceDocumentHash: String
  public let evidence: SourceEvidence
  public let confidence: ConfidenceLevel
  public let needsReview: Bool
  public let draft: ActionDraft
  public var destination: ActionExportDestination

  public init(
    actionID: String,
    category: ActionCategory,
    sourceDocumentHash: String,
    evidence: SourceEvidence,
    confidence: ConfidenceLevel,
    needsReview: Bool,
    draft: ActionDraft,
    destination: ActionExportDestination
  ) {
    self.actionID = actionID
    self.category = category
    self.sourceDocumentHash = sourceDocumentHash
    self.evidence = evidence
    self.confidence = confidence
    self.needsReview = needsReview
    self.draft = draft
    self.destination = destination
  }
}

public struct ActionExportPreview: Equatable, Sendable {
  public var items: [ActionExportPreviewItem]
  public let excludedUnconfirmedActionCount: Int
  public var includeResponsiblePartyInNotes: Bool

  public var requiresReviewAcknowledgement: Bool {
    items.contains { $0.destination != .skip && $0.needsReview }
  }

  public init(
    items: [ActionExportPreviewItem],
    excludedUnconfirmedActionCount: Int,
    includeResponsiblePartyInNotes: Bool = false
  ) {
    self.items = items
    self.excludedUnconfirmedActionCount = excludedUnconfirmedActionCount
    self.includeResponsiblePartyInNotes = includeResponsiblePartyInNotes
  }
}

public enum ActionExportPreviewBuilder {
  public static func build(
    sourceDocumentHash: String,
    actions: [ActionCard],
    drafts: [ActionDraft],
    confirmedActionIDs: Set<String>,
    destinationOverrides: [String: ActionExportDestination] = [:],
    includeResponsiblePartyInNotes: Bool = false
  ) -> ActionExportPreview {
    let draftsByActionID = Dictionary(
      uniqueKeysWithValues: drafts.map { ($0.sourceActionID, $0) }
    )
    let items = actions.compactMap { action -> ActionExportPreviewItem? in
      guard confirmedActionIDs.contains(action.id),
        let draft = draftsByActionID[action.id]
      else {
        return nil
      }
      return ActionExportPreviewItem(
        actionID: action.id,
        category: action.category,
        sourceDocumentHash: sourceDocumentHash,
        evidence: action.evidence,
        confidence: action.confidence,
        needsReview: action.needsReview,
        draft: draft,
        destination: destinationOverrides[action.id]
          ?? ActionExportDefaults.destination(for: action.category)
      )
    }
    return ActionExportPreview(
      items: items,
      excludedUnconfirmedActionCount: actions.count
        - actions.lazy.filter { confirmedActionIDs.contains($0.id) }.count,
      includeResponsiblePartyInNotes: includeResponsiblePartyInNotes
    )
  }
}

public enum ActionExportValidationIssue: Equatable, Hashable, Sendable {
  case emptyTitle
  case invalidResponsibleParty(ResponsiblePartyValidationIssue)
  case ambiguousDate
  case calendarRequiresDate
  case reviewAcknowledgementRequired
}

public struct ActionExportRequest: Equatable, Identifiable, Sendable {
  public var id: String { actionID }

  public let actionID: String
  public let destination: ActionExportDestination
  public let title: String
  public let notes: String?
  public let dateTime: ActionDateTime?
  public let location: String?
  public let isAllDay: Bool
  public let durationMinutes: Int?
  public let markerCanonicalPayload: Data

  public init(
    actionID: String,
    destination: ActionExportDestination,
    title: String,
    notes: String?,
    dateTime: ActionDateTime?,
    location: String?,
    isAllDay: Bool,
    durationMinutes: Int?,
    markerCanonicalPayload: Data
  ) {
    self.actionID = actionID
    self.destination = destination
    self.title = title
    self.notes = notes
    self.dateTime = dateTime
    self.location = location
    self.isAllDay = isAllDay
    self.durationMinutes = durationMinutes
    self.markerCanonicalPayload = markerCanonicalPayload
  }
}

public struct ActionExportRequestBuildResult: Equatable, Sendable {
  public let request: ActionExportRequest?
  public let issues: [ActionExportValidationIssue]

  public init(
    request: ActionExportRequest?,
    issues: [ActionExportValidationIssue]
  ) {
    self.request = request
    self.issues = issues
  }
}

public struct ActionExportPresentation: Equatable, Sendable {
  public let title: String?
  public let bringLabel: String
  public let contactLabel: String
  public let locationLabel: String
  public let responsibleLabel: String
  public let meLabel: String
  public let familyOrCaregiverLabel: String
  public let separator: String

  public init(
    title: String? = nil,
    bringLabel: String = "Bring",
    contactLabel: String = "Contact",
    locationLabel: String = "Location",
    responsibleLabel: String = "Responsible",
    meLabel: String = "Me",
    familyOrCaregiverLabel: String = "Family / caregiver",
    separator: String = ": "
  ) {
    self.title = title
    self.bringLabel = bringLabel
    self.contactLabel = contactLabel
    self.locationLabel = locationLabel
    self.responsibleLabel = responsibleLabel
    self.meLabel = meLabel
    self.familyOrCaregiverLabel = familyOrCaregiverLabel
    self.separator = separator
  }

  public static let english = ActionExportPresentation()
}

public enum ActionExportRequestBuilder {
  public static func build(
    from item: ActionExportPreviewItem,
    includeResponsiblePartyInNotes: Bool,
    acknowledgesReviewWarnings: Bool,
    presentation: ActionExportPresentation = .english
  ) -> ActionExportRequestBuildResult {
    guard item.destination != .skip else {
      return ActionExportRequestBuildResult(request: nil, issues: [])
    }

    let canonicalTitle = normalizedText(item.draft.title)
    let title = normalizedText(presentation.title ?? item.draft.title)
    var issues: [ActionExportValidationIssue] = []
    if title.isEmpty {
      issues.append(.emptyTitle)
    }
    if let responsibleIssue = item.draft.responsibleParty.validationIssue {
      issues.append(.invalidResponsibleParty(responsibleIssue))
    }
    if item.draft.dateTime?.isAmbiguous == true {
      issues.append(.ambiguousDate)
    }
    if item.destination == .calendar, item.draft.dateTime == nil {
      issues.append(.calendarRequiresDate)
    }
    if item.needsReview, !acknowledgesReviewWarnings {
      issues.append(.reviewAcknowledgementRequired)
    }
    guard issues.isEmpty else {
      return ActionExportRequestBuildResult(request: nil, issues: issues)
    }

    let isTimedCalendar = item.destination == .calendar && item.draft.dateTime?.hasTime == true
    let requestNotes = notes(
      for: item.draft,
      evidenceText: item.evidence.text,
      destination: item.destination,
      includeResponsibleParty: includeResponsiblePartyInNotes,
      presentation: presentation
    )
    let request = ActionExportRequest(
      actionID: item.actionID,
      destination: item.destination,
      title: title,
      notes: requestNotes,
      dateTime: item.draft.dateTime,
      location: normalizedOptionalText(item.draft.location),
      isAllDay: item.destination == .calendar && !isTimedCalendar,
      durationMinutes: isTimedCalendar ? 60 : nil,
      markerCanonicalPayload: markerCanonicalPayload(
        for: item,
        title: canonicalTitle
      )
    )
    return ActionExportRequestBuildResult(request: request, issues: [])
  }

  private static func notes(
    for draft: ActionDraft,
    evidenceText: String,
    destination: ActionExportDestination,
    includeResponsibleParty: Bool,
    presentation: ActionExportPresentation
  ) -> String? {
    var lines: [String] = []
    let detail = normalizedText(draft.detail)
    if !detail.isEmpty,
      detail != normalizedText(draft.title),
      detail != normalizedText(evidenceText)
    {
      lines.append(detail)
    }
    let items = normalizedItems(draft.items)
    if !items.isEmpty {
      lines.append(
        "\(presentation.bringLabel)\(presentation.separator)\(items.joined(separator: ", "))"
      )
    }
    if let contact = normalizedOptionalText(draft.contact) {
      lines.append("\(presentation.contactLabel)\(presentation.separator)\(contact)")
    }
    if destination == .reminder,
      let location = normalizedOptionalText(draft.location)
    {
      lines.append("\(presentation.locationLabel)\(presentation.separator)\(location)")
    }
    if includeResponsibleParty {
      lines.append(
        "\(presentation.responsibleLabel)\(presentation.separator)\(responsiblePartyLabel(draft.responsibleParty, presentation: presentation))"
      )
    }
    return lines.isEmpty ? nil : lines.joined(separator: "\n")
  }

  private static func responsiblePartyLabel(
    _ party: ResponsibleParty,
    presentation: ActionExportPresentation
  ) -> String {
    switch party {
    case .me:
      return presentation.meLabel
    case .familyOrCaregiver:
      return presentation.familyOrCaregiverLabel
    case .custom(let name):
      return normalizedText(name)
    }
  }

  private static func markerCanonicalPayload(
    for item: ActionExportPreviewItem,
    title: String
  ) -> Data {
    let normalizedItems = normalizedItems(item.draft.items)
    let fields = [
      field("version", "1"),
      field("sourceHash", item.sourceDocumentHash),
      field("rule", item.evidence.ruleID),
      field("rangeLocation", String(item.evidence.range.location)),
      field("rangeLength", String(item.evidence.range.length)),
      field("destination", item.destination.rawValue),
      field("title", title),
      field(
        "detail",
        markerDetail(for: item)
      ),
      optionalField("dateTime", item.draft.dateTime?.iso8601Local),
      optionalField("location", normalizedOptionalText(item.draft.location)),
      field("itemCount", String(normalizedItems.count)),
      field("items", normalizedItems.map(lengthPrefixed).joined()),
      optionalField("contact", normalizedOptionalText(item.draft.contact)),
      optionalField("notes", nil),
    ]
    return Data(fields.joined(separator: "|").utf8)
  }

  private static func markerDetail(for item: ActionExportPreviewItem) -> String {
    let detail = normalizedText(item.draft.detail)
    return detail == normalizedText(item.evidence.text) ? "" : detail
  }

  private static func normalizedItems(_ items: [String]) -> [String] {
    items.map(normalizedText).filter { !$0.isEmpty }
  }

  private static func normalizedOptionalText(_ value: String?) -> String? {
    guard let value else { return nil }
    let normalized = normalizedText(value)
    return normalized.isEmpty ? nil : normalized
  }

  private static func normalizedText(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
      .precomposedStringWithCanonicalMapping
  }

  private static func field(_ name: String, _ value: String) -> String {
    "\(name)=s\(lengthPrefixed(value))"
  }

  private static func optionalField(_ name: String, _ value: String?) -> String {
    guard let value else { return "\(name)=n" }
    return field(name, value)
  }

  private static func lengthPrefixed(_ value: String) -> String {
    "\(value.utf8.count):\(value)"
  }
}

public enum ActionExportFailure: Error, Equatable, Sendable {
  case permissionDenied
  case permissionRestricted
  case fullAccessRequired
  case noDefaultCalendar
  case noDefaultReminderList
  case invalidDate
  case duplicateLookupFailed
  case ambiguousDuplicate
  case alreadyInProgress
  case saveFailed
  case itemChanged
  case itemNotFound
  case invalidExporterResult
  case invalidReceipt
  case removeFailed
}

public struct ExportReceiptItem: Equatable, Sendable {
  public let actionID: String
  public let destination: ActionExportDestination
  public let calendarItemIdentifier: String?
  public let markerURLString: String
  public let dateTime: ActionDateTime?

  public init(
    actionID: String,
    destination: ActionExportDestination,
    calendarItemIdentifier: String?,
    markerURLString: String,
    dateTime: ActionDateTime?
  ) {
    self.actionID = actionID
    self.destination = destination
    self.calendarItemIdentifier = calendarItemIdentifier
    self.markerURLString = markerURLString
    self.dateTime = dateTime
  }
}

public enum ActionExportItemOutcome: Equatable, Sendable {
  case created(ExportReceiptItem)
  case alreadyAdded
  case skipped
  case failed(ActionExportFailure)
}

public struct ActionExportItemResult: Equatable, Identifiable, Sendable {
  public var id: String { actionID }

  public let actionID: String
  public let outcome: ActionExportItemOutcome

  public init(actionID: String, outcome: ActionExportItemOutcome) {
    self.actionID = actionID
    self.outcome = outcome
  }
}

public struct ExportReceipt: Equatable, Identifiable, Sendable {
  public var id: UUID { operationID }

  public let operationID: UUID
  public let items: [ExportReceiptItem]

  public init(operationID: UUID, items: [ExportReceiptItem]) {
    self.operationID = operationID
    self.items = items
  }
}

public struct ActionExportBatchResult: Equatable, Sendable {
  public let operationID: UUID
  public let results: [ActionExportItemResult]
  public let receipt: ExportReceipt?

  public init(operationID: UUID = UUID(), results: [ActionExportItemResult]) {
    self.operationID = operationID
    self.results = results
    let createdItems = results.compactMap { result -> ExportReceiptItem? in
      guard case .created(let receipt) = result.outcome else { return nil }
      return receipt
    }
    self.receipt =
      createdItems.isEmpty
      ? nil : ExportReceipt(operationID: operationID, items: createdItems)
  }
}

public enum ActionUndoItemOutcome: Equatable, Sendable {
  case removed
  case alreadyRemoved
  case failed(ActionExportFailure)
}

public struct ActionUndoItemResult: Equatable, Identifiable, Sendable {
  public var id: String { actionID }

  public let actionID: String
  public let outcome: ActionUndoItemOutcome

  public init(actionID: String, outcome: ActionUndoItemOutcome) {
    self.actionID = actionID
    self.outcome = outcome
  }
}

public struct ActionUndoBatchResult: Equatable, Sendable {
  public let operationID: UUID
  public let results: [ActionUndoItemResult]

  public init(operationID: UUID, results: [ActionUndoItemResult]) {
    self.operationID = operationID
    self.results = results
  }
}

@MainActor
public protocol ActionExporting: AnyObject {
  func export(_ requests: [ActionExportRequest]) async -> ActionExportBatchResult
  func undo(_ receipt: ExportReceipt) async -> ActionUndoBatchResult
}

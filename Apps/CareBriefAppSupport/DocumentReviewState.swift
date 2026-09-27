import CareBriefCore
import Foundation

public struct DocumentReviewState: Equatable, Sendable {
  public private(set) var inputText: String
  public private(set) var language: DocumentLanguage
  public private(set) var sourceDocument: SourceDocument?
  public private(set) var extractionResult: ExtractionResult?
  public private(set) var confirmedActionIDs: Set<String>
  private var draftsByActionID: [String: ActionDraft]

  public var actions: [ActionCard] {
    extractionResult?.actions ?? []
  }

  public var warnings: [String] {
    extractionResult?.warnings ?? []
  }

  public var drafts: [ActionDraft] {
    actions.compactMap { draftsByActionID[$0.id] }
  }

  public var requiresReview: Bool {
    extractionResult?.requiresReview ?? false
  }

  public var actionsRequiringReviewCount: Int {
    actions.filter(\.needsReview).count
  }

  public var confirmedActionCount: Int {
    confirmedActionIDs.count
  }

  public var pendingActionCount: Int {
    actions.count - confirmedActionCount
  }

  public init(
    inputText: String = "",
    language: DocumentLanguage = .unknown
  ) {
    self.inputText = inputText
    self.language = language
    self.sourceDocument = nil
    self.extractionResult = nil
    self.confirmedActionIDs = []
    self.draftsByActionID = [:]
  }

  @discardableResult
  public mutating func extract(
    using extractor: any DocumentActionExtracting = RuleBasedActionExtractor(),
    documentID: UUID = UUID()
  ) -> ExtractionResult {
    let document = SourceDocument(
      id: documentID,
      text: inputText,
      language: language
    )
    let result = extractor.extract(from: document)
    sourceDocument = document
    extractionResult = result
    confirmedActionIDs.removeAll()
    draftsByActionID = Dictionary(
      uniqueKeysWithValues: result.actions.map { ($0.id, ActionDraft(action: $0)) }
    )
    return result
  }

  public mutating func setInputText(
    _ text: String,
    language newLanguage: DocumentLanguage? = nil
  ) {
    let resolvedLanguage = newLanguage ?? language
    guard text != inputText || resolvedLanguage != language else { return }

    inputText = text
    language = resolvedLanguage
    sourceDocument = nil
    extractionResult = nil
    confirmedActionIDs.removeAll()
    draftsByActionID.removeAll()
  }

  public func draft(forActionID actionID: String) -> ActionDraft? {
    draftsByActionID[actionID]
  }

  @discardableResult
  public mutating func updateDraft(_ draft: ActionDraft) -> Bool {
    guard let currentDraft = draftsByActionID[draft.sourceActionID],
      actions.contains(where: { $0.id == draft.sourceActionID })
    else {
      return false
    }

    guard draft != currentDraft else { return true }
    draftsByActionID[draft.sourceActionID] = draft
    confirmedActionIDs.remove(draft.sourceActionID)
    return true
  }

  public func isDraftEdited(actionID: String) -> Bool {
    guard let action = actions.first(where: { $0.id == actionID }),
      let draft = draftsByActionID[actionID]
    else {
      return false
    }
    return draft != ActionDraft(action: action)
  }

  public func isConfirmed(actionID: String) -> Bool {
    confirmedActionIDs.contains(actionID)
  }

  @discardableResult
  public mutating func setConfirmation(
    _ isConfirmed: Bool,
    forActionID actionID: String
  ) -> Bool {
    guard extractionResult?.actions.contains(where: { $0.id == actionID }) == true else {
      return false
    }

    if isConfirmed {
      confirmedActionIDs.insert(actionID)
    } else {
      confirmedActionIDs.remove(actionID)
    }
    return true
  }

  @discardableResult
  public mutating func toggleConfirmation(forActionID actionID: String) -> Bool {
    setConfirmation(!isConfirmed(actionID: actionID), forActionID: actionID)
  }

  public mutating func clearConfirmations() {
    confirmedActionIDs.removeAll()
  }

  public mutating func reset() {
    self = DocumentReviewState()
  }
}

import CareBriefCore
import Foundation
import Testing

@testable import CareBriefAppSupport

@Suite struct DocumentReviewStateTests {
  @Test func extractionSeedsEditableDraftsWithoutChangingSourceActions() throws {
    var state = DocumentReviewState(inputText: "請於 2026 年 8 月 15 日上午 9 時到威爾斯親王醫院覆診。")

    state.extract(using: RuleBasedActionExtractor())

    let action = try #require(state.actions.first)
    let draft = try #require(state.draft(forActionID: action.id))
    #expect(state.drafts.count == state.actions.count)
    #expect(draft.sourceActionID == action.id)
    #expect(draft.title == action.title)
    #expect(draft.detail == action.detail)
    #expect(draft.dateTime == action.dateTime)
    #expect(draft.location == action.location)
    #expect(draft.items == action.items)
    #expect(draft.contact == action.contact)
    #expect(draft.responsibleParty == .me)
    #expect(action.evidence.resolves(in: try #require(state.sourceDocument)))
  }

  @Test func editingADraftInvalidatesConfirmationWithoutChangingSourceEvidence() throws {
    var state = DocumentReviewState(inputText: "請攜帶身份證。")
    state.extract(using: RuleBasedActionExtractor())
    let sourceAction = try #require(state.actions.first)
    _ = state.setConfirmation(true, forActionID: sourceAction.id)
    var draft = try #require(state.draft(forActionID: sourceAction.id))

    draft.title = "Bring identity document"
    let accepted = state.updateDraft(draft)

    #expect(accepted)
    #expect(!state.isConfirmed(actionID: sourceAction.id))
    #expect(state.isDraftEdited(actionID: sourceAction.id))
    #expect(state.actions.first == sourceAction)
    #expect(sourceAction.evidence.resolves(in: try #require(state.sourceDocument)))
  }

  @Test func submittingAnUnchangedDraftPreservesConfirmation() throws {
    var state = DocumentReviewState(inputText: "請攜帶身份證。")
    state.extract(using: RuleBasedActionExtractor())
    let action = try #require(state.actions.first)
    let unchangedDraft = try #require(state.draft(forActionID: action.id))
    _ = state.setConfirmation(true, forActionID: action.id)

    let accepted = state.updateDraft(unchangedDraft)

    #expect(accepted)
    #expect(state.isConfirmed(actionID: action.id))
    #expect(!state.isDraftEdited(actionID: action.id))
  }

  @Test func everyEditableDraftFieldInvalidatesConfirmation() throws {
    var extractedState = DocumentReviewState(
      inputText: "請於 2026 年 8 月 15 日上午 9 時到威爾斯親王醫院覆診，並攜帶身份證。如有查詢請致電 2123 4567。"
    )
    extractedState.extract(using: RuleBasedActionExtractor())
    let action = try #require(extractedState.actions.first)
    let originalDraft = try #require(extractedState.draft(forActionID: action.id))

    var title = originalDraft
    title.title += "（已修改）"
    var detail = originalDraft
    detail.detail += "（已修改）"
    var dateTime = originalDraft
    dateTime.dateTime = ActionDateTime(year: 2026, month: 8, day: 16, hour: 10)
    var location = originalDraft
    location.location = "另一間診所"
    var items = originalDraft
    items.items.append("覆診信")
    var contact = originalDraft
    contact.contact = "9876 5432"
    var responsibleParty = originalDraft
    responsibleParty.responsibleParty = .familyOrCaregiver

    for editedDraft in [title, detail, dateTime, location, items, contact, responsibleParty] {
      var state = extractedState
      let acceptedConfirmation = state.setConfirmation(true, forActionID: action.id)

      let acceptedDraft = state.updateDraft(editedDraft)
      #expect(acceptedConfirmation)
      #expect(acceptedDraft)
      #expect(!state.isConfirmed(actionID: action.id))
      #expect(state.isDraftEdited(actionID: action.id))
    }
  }

  @Test func unknownDraftCannotMutateReviewStateOrConfirmation() throws {
    var state = DocumentReviewState(inputText: "請攜帶身份證。")
    state.extract(using: RuleBasedActionExtractor())
    let action = try #require(state.actions.first)
    let acceptedConfirmation = state.setConfirmation(true, forActionID: action.id)
    #expect(acceptedConfirmation)
    let originalDraft = try #require(state.draft(forActionID: action.id))
    let unknownDraft = ActionDraft(
      sourceActionID: "unknown",
      title: "Unknown",
      detail: "Unknown",
      dateTime: nil,
      location: nil,
      items: [],
      contact: nil
    )

    let acceptedDraft = state.updateDraft(unknownDraft)
    #expect(!acceptedDraft)
    #expect(state.draft(forActionID: action.id) == originalDraft)
    #expect(state.isConfirmed(actionID: action.id))
  }

  @Test func draftEditsCannotChangeSourceEvidenceRuleConfidenceOrReviewWarning() throws {
    var state = DocumentReviewState(inputText: "地點：Prince of Wales Hospital")
    state.extract(using: RuleBasedActionExtractor())
    let sourceAction = try #require(state.actions.first)
    let originalEvidence = sourceAction.evidence
    let originalRule = sourceAction.evidence.ruleID
    let originalConfidence = sourceAction.confidence
    let originalNeedsReview = sourceAction.needsReview
    var draft = try #require(state.draft(forActionID: sourceAction.id))

    draft.title = "Edited title"
    draft.detail = "Edited detail"
    draft.dateTime = ActionDateTime(year: 2026, month: 8, day: 15, hour: 9)
    draft.location = "Edited location"
    draft.items = ["Edited item"]
    draft.contact = "2123 4567"
    draft.responsibleParty = .familyOrCaregiver
    let accepted = state.updateDraft(draft)
    #expect(accepted)

    let retainedAction = try #require(state.actions.first)
    #expect(retainedAction == sourceAction)
    #expect(retainedAction.evidence == originalEvidence)
    #expect(retainedAction.evidence.ruleID == originalRule)
    #expect(retainedAction.confidence == originalConfidence)
    #expect(retainedAction.needsReview == originalNeedsReview)
  }

  @Test func extractedActionsRemainTraceableToTheSavedSource() throws {
    let text = "請於 2026 年 8 月 15 日上午 9 時到威爾斯親王醫院覆診，並攜帶身份證。"
    var state = DocumentReviewState(inputText: text, language: .traditionalChinese)

    state.extract(using: RuleBasedActionExtractor())

    let source = try #require(state.sourceDocument)
    let result = try #require(state.extractionResult)
    #expect(!result.actions.isEmpty)
    #expect(result.actions.allSatisfy { $0.evidence.resolves(in: source) })
  }

  @Test func onlyExtractedActionsCanBeConfirmed() throws {
    var state = DocumentReviewState(inputText: "請攜帶身份證。")
    state.extract(using: RuleBasedActionExtractor())
    let action = try #require(state.extractionResult?.actions.first)

    let acceptedKnownID = state.setConfirmation(true, forActionID: action.id)
    #expect(acceptedKnownID)
    #expect(state.isConfirmed(actionID: action.id))
    let acceptedUnknownID = state.setConfirmation(true, forActionID: "unknown")
    #expect(!acceptedUnknownID)
    #expect(state.confirmedActionIDs == Set([action.id]))
  }

  @Test func changingInputInvalidatesDerivedReviewState() throws {
    var state = DocumentReviewState(inputText: "請攜帶身份證。")
    state.extract(using: RuleBasedActionExtractor())
    let actionID = try #require(state.extractionResult?.actions.first?.id)
    _ = state.setConfirmation(true, forActionID: actionID)

    state.setInputText("請攜帶覆診紙。", language: .traditionalChinese)

    #expect(state.inputText == "請攜帶覆診紙。")
    #expect(state.language == .traditionalChinese)
    #expect(state.sourceDocument == nil)
    #expect(state.extractionResult == nil)
    #expect(state.confirmedActionIDs.isEmpty)
    #expect(state.drafts.isEmpty)
  }

  @Test func confirmationNeverHidesExtractorReviewRequirements() throws {
    var state = DocumentReviewState(inputText: "地點：Prince of Wales Hospital")
    state.extract(using: RuleBasedActionExtractor())
    let action = try #require(state.actions.first)

    #expect(state.requiresReview)
    #expect(state.actionsRequiringReviewCount == 1)
    #expect(state.confirmedActionCount == 0)
    #expect(state.pendingActionCount == 1)

    _ = state.setConfirmation(true, forActionID: action.id)

    #expect(state.requiresReview)
    #expect(state.actionsRequiringReviewCount == 1)
    #expect(state.confirmedActionCount == 1)
    #expect(state.pendingActionCount == 0)
  }

  @Test func clearingConfirmationsAndResettingHaveDistinctEffects() throws {
    var state = DocumentReviewState(inputText: "請攜帶身份證。")
    state.extract(using: RuleBasedActionExtractor())
    let actionID = try #require(state.actions.first?.id)

    let toggled = state.toggleConfirmation(forActionID: actionID)
    #expect(toggled)
    state.clearConfirmations()
    #expect(state.confirmedActionIDs.isEmpty)
    #expect(!state.actions.isEmpty)
    #expect(state.sourceDocument != nil)

    state.reset()
    #expect(state.inputText.isEmpty)
    #expect(state.language == .unknown)
    #expect(state.sourceDocument == nil)
    #expect(state.extractionResult == nil)
    #expect(state.confirmedActionIDs.isEmpty)
    #expect(state.drafts.isEmpty)
  }

  @Test func extractingAgainClearsConfirmationForThePreviousRun() throws {
    var state = DocumentReviewState(inputText: "請攜帶身份證。")
    state.extract(
      using: RuleBasedActionExtractor(),
      documentID: UUID(uuidString: "00000000-0000-0000-0000-000000000041")!
    )
    let actionID = try #require(state.actions.first?.id)
    _ = state.setConfirmation(true, forActionID: actionID)
    var editedDraft = try #require(state.draft(forActionID: actionID))
    editedDraft.title = "Edited title"
    let acceptedDraft = state.updateDraft(editedDraft)
    #expect(acceptedDraft)

    state.extract(
      using: RuleBasedActionExtractor(),
      documentID: UUID(uuidString: "00000000-0000-0000-0000-000000000042")!
    )

    #expect(state.confirmedActionIDs.isEmpty)
    #expect(state.actions.first?.id != actionID)
    #expect(state.drafts.map(\.sourceActionID) == state.actions.map(\.id))
    #expect(state.drafts == state.actions.map { ActionDraft(action: $0) })
    #expect(state.actions.allSatisfy { !state.isDraftEdited(actionID: $0.id) })
  }

  @Test func sameTextOCRReplacementStartsANewUnreviewedState() throws {
    let recognizedText = "請攜帶身份證。"
    var previousState = DocumentReviewState(inputText: recognizedText)
    previousState.extract(using: RuleBasedActionExtractor())
    let action = try #require(previousState.actions.first)
    let acceptedConfirmation = previousState.setConfirmation(true, forActionID: action.id)
    #expect(acceptedConfirmation)

    let replacementState = DocumentReviewState(inputText: recognizedText)

    #expect(replacementState.inputText == recognizedText)
    #expect(replacementState.sourceDocument == nil)
    #expect(replacementState.extractionResult == nil)
    #expect(replacementState.confirmedActionIDs.isEmpty)
    #expect(replacementState.drafts.isEmpty)
  }

  @Test func extractionCreatesDraftsAndRealEditClearsOnlyItsConfirmation() throws {
    var state = DocumentReviewState(inputText: "請攜帶身份證。")
    state.extract(using: RuleBasedActionExtractor())
    var draft = try #require(state.drafts.first)
    _ = state.setConfirmation(true, forActionID: draft.id)

    let acceptedUnchanged = state.updateDraft(draft)
    #expect(acceptedUnchanged)
    #expect(state.isConfirmed(actionID: draft.id))

    draft.title = "攜帶身份證正本"
    let acceptedEdit = state.updateDraft(draft)
    #expect(acceptedEdit)
    #expect(!state.isConfirmed(actionID: draft.id))
    #expect(state.draft(forActionID: draft.id)?.title == "攜帶身份證正本")
  }

  @Test func inputChangeAndResetClearDrafts() {
    var state = DocumentReviewState(inputText: "請攜帶身份證。")
    state.extract(using: RuleBasedActionExtractor())
    #expect(!state.drafts.isEmpty)

    state.setInputText("請攜帶覆診紙。")
    #expect(state.drafts.isEmpty)

    state.extract(using: RuleBasedActionExtractor())
    state.reset()
    #expect(state.drafts.isEmpty)
  }

  @Test func unsupportedInputRetainsWarningDrivenReviewState() {
    var state = DocumentReviewState(inputText: "這是一封一般資料通知。")

    state.extract(using: RuleBasedActionExtractor())

    #expect(state.actions.isEmpty)
    #expect(state.actionsRequiringReviewCount == 0)
    #expect(state.warnings.count == 1)
    #expect(state.requiresReview)
  }
}

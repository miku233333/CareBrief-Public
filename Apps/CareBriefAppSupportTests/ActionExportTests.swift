import CareBriefCore
import Foundation
import Testing

@testable import CareBriefAppSupport

@Suite struct ActionExportTests {
  @Test func categoriesReceiveTheApprovedDefaultDestinations() {
    #expect(ActionExportDefaults.destination(for: .appointment) == .calendar)
    #expect(ActionExportDefaults.destination(for: .deadline) == .reminder)
    #expect(ActionExportDefaults.destination(for: .preparation) == .reminder)
    #expect(ActionExportDefaults.destination(for: .requiredItem) == .reminder)
    #expect(ActionExportDefaults.destination(for: .nextStep) == .reminder)
    #expect(ActionExportDefaults.destination(for: .contact) == .skip)
    #expect(ActionExportDefaults.destination(for: .location) == .skip)
  }

  @Test func previewIncludesOnlyConfirmedDraftsAndAppliesOverrides() throws {
    let appointment = try makeAction(id: "appointment", category: .appointment)
    let nextStep = try makeAction(id: "next-step", category: .nextStep)

    let preview = ActionExportPreviewBuilder.build(
      sourceDocumentHash: "source-hash",
      actions: [appointment, nextStep],
      drafts: [ActionDraft(action: appointment), ActionDraft(action: nextStep)],
      confirmedActionIDs: [appointment.id],
      destinationOverrides: [appointment.id: .reminder]
    )

    #expect(preview.items.map(\.actionID) == [appointment.id])
    #expect(preview.items.first?.destination == .reminder)
    #expect(preview.excludedUnconfirmedActionCount == 1)
  }

  @Test func previewCountsUnconfirmedSourceActionsWithoutTrustingUnknownIDs() throws {
    let appointment = try makeAction(id: "appointment", category: .appointment)
    let nextStep = try makeAction(id: "next-step", category: .nextStep)

    let preview = ActionExportPreviewBuilder.build(
      sourceDocumentHash: "source-hash",
      actions: [appointment, nextStep],
      drafts: [ActionDraft(action: appointment), ActionDraft(action: nextStep)],
      confirmedActionIDs: [appointment.id, "unknown-action"]
    )

    #expect(preview.items.map(\.actionID) == [appointment.id])
    #expect(preview.excludedUnconfirmedActionCount == 1)
  }

  @Test func skippedNeedsReviewActionDoesNotBlockOtherSelectedActions() throws {
    let appointment = try makeAction(id: "appointment", category: .appointment)
    let contact = try makeAction(
      id: "contact",
      category: .contact,
      needsReview: true
    )
    let preview = ActionExportPreviewBuilder.build(
      sourceDocumentHash: "source-hash",
      actions: [appointment, contact],
      drafts: [ActionDraft(action: appointment), ActionDraft(action: contact)],
      confirmedActionIDs: [appointment.id, contact.id]
    )

    #expect(preview.items.first(where: { $0.actionID == contact.id })?.destination == .skip)
    #expect(!preview.requiresReviewAcknowledgement)
  }

  @Test func calendarRequestsUseAllDayOrSixtyMinuteTiming() throws {
    let allDayAction = try makeAction(
      id: "all-day",
      category: .appointment,
      dateTime: ActionDateTime(year: 2026, month: 8, day: 15)
    )
    let timedAction = try makeAction(
      id: "timed",
      category: .appointment,
      dateTime: ActionDateTime(year: 2026, month: 8, day: 15, hour: 9)
    )
    let preview = ActionExportPreviewBuilder.build(
      sourceDocumentHash: "source-hash",
      actions: [allDayAction, timedAction],
      drafts: [ActionDraft(action: allDayAction), ActionDraft(action: timedAction)],
      confirmedActionIDs: [allDayAction.id, timedAction.id]
    )

    let requests = preview.items.map {
      ActionExportRequestBuilder.build(
        from: $0,
        includeResponsiblePartyInNotes: false,
        acknowledgesReviewWarnings: false
      )
    }
    let allDayRequest = try #require(requests[0].request)
    let timedRequest = try #require(requests[1].request)
    #expect(allDayRequest.isAllDay)
    #expect(allDayRequest.durationMinutes == nil)
    #expect(!timedRequest.isAllDay)
    #expect(timedRequest.durationMinutes == 60)
  }

  @Test func reminderMayOmitDueDateWhileCalendarMayNot() throws {
    let action = try makeAction(id: "no-date", category: .nextStep)
    let item = try #require(
      ActionExportPreviewBuilder.build(
        sourceDocumentHash: "source-hash",
        actions: [action],
        drafts: [ActionDraft(action: action)],
        confirmedActionIDs: [action.id]
      ).items.first
    )

    let reminder = ActionExportRequestBuilder.build(
      from: item,
      includeResponsiblePartyInNotes: false,
      acknowledgesReviewWarnings: false
    )
    #expect(reminder.issues.isEmpty)
    #expect(reminder.request?.destination == .reminder)
    #expect(reminder.request?.dateTime == nil)

    var calendarItem = item
    calendarItem.destination = .calendar
    let calendar = ActionExportRequestBuilder.build(
      from: calendarItem,
      includeResponsiblePartyInNotes: false,
      acknowledgesReviewWarnings: false
    )
    #expect(calendar.request == nil)
    #expect(calendar.issues == [.calendarRequiresDate])
  }

  @Test func ambiguousDatesAndUnacknowledgedReviewWarningsCannotExport() throws {
    let action = try makeAction(
      id: "ambiguous",
      category: .appointment,
      dateTime: ActionDateTime(
        year: 2026,
        month: 8,
        day: 15,
        isAmbiguous: true
      ),
      needsReview: true
    )
    let item = try #require(
      ActionExportPreviewBuilder.build(
        sourceDocumentHash: "source-hash",
        actions: [action],
        drafts: [ActionDraft(action: action)],
        confirmedActionIDs: [action.id]
      ).items.first
    )

    let blocked = ActionExportRequestBuilder.build(
      from: item,
      includeResponsiblePartyInNotes: false,
      acknowledgesReviewWarnings: false
    )
    #expect(blocked.request == nil)
    #expect(blocked.issues.contains(.ambiguousDate))
    #expect(blocked.issues.contains(.reviewAcknowledgementRequired))

    var resolvedDraft = item.draft
    resolvedDraft.dateTime = ActionDateTime(year: 2026, month: 8, day: 15)
    let resolvedItem = ActionExportPreviewItem(
      actionID: item.actionID,
      category: item.category,
      sourceDocumentHash: item.sourceDocumentHash,
      evidence: item.evidence,
      confidence: item.confidence,
      needsReview: item.needsReview,
      draft: resolvedDraft,
      destination: item.destination
    )
    let allowed = ActionExportRequestBuilder.build(
      from: resolvedItem,
      includeResponsiblePartyInNotes: false,
      acknowledgesReviewWarnings: true
    )
    #expect(allowed.issues.isEmpty)
    #expect(allowed.request != nil)
  }

  @Test func ambiguousDateAlsoBlocksReminderExport() throws {
    let action = try makeAction(
      id: "ambiguous-reminder",
      category: .preparation,
      dateTime: ActionDateTime(
        year: 2026,
        month: 8,
        day: 15,
        isAmbiguous: true
      )
    )
    let item = try #require(
      ActionExportPreviewBuilder.build(
        sourceDocumentHash: "source-hash",
        actions: [action],
        drafts: [ActionDraft(action: action)],
        confirmedActionIDs: [action.id]
      ).items.first
    )

    #expect(item.destination == .reminder)
    let result = ActionExportRequestBuilder.build(
      from: item,
      includeResponsiblePartyInNotes: false,
      acknowledgesReviewWarnings: true
    )
    #expect(result.request == nil)
    #expect(result.issues == [.ambiguousDate])
  }

  @Test func exportRejectsInvalidResponsiblePartyAndAcceptsEightyCharacters() throws {
    let action = try makeAction(
      id: "responsible-party",
      category: .appointment,
      dateTime: ActionDateTime(year: 2026, month: 8, day: 15)
    )
    var validDraft = ActionDraft(action: action)
    validDraft.responsibleParty = .custom(String(repeating: "家", count: 80))
    let validRequest = try makeExportRequest(action: action, draft: validDraft)
    #expect(validRequest.actionID == action.id)

    var emptyNameItem = try #require(
      ActionExportPreviewBuilder.build(
        sourceDocumentHash: "source-hash",
        actions: [action],
        drafts: [ActionDraft(action: action)],
        confirmedActionIDs: [action.id]
      ).items.first
    )
    var emptyNameDraft = emptyNameItem.draft
    emptyNameDraft.responsibleParty = .custom("  ")
    emptyNameItem = ActionExportPreviewItem(
      actionID: emptyNameItem.actionID,
      category: emptyNameItem.category,
      sourceDocumentHash: emptyNameItem.sourceDocumentHash,
      evidence: emptyNameItem.evidence,
      confidence: emptyNameItem.confidence,
      needsReview: emptyNameItem.needsReview,
      draft: emptyNameDraft,
      destination: emptyNameItem.destination
    )
    let emptyNameResult = ActionExportRequestBuilder.build(
      from: emptyNameItem,
      includeResponsiblePartyInNotes: false,
      acknowledgesReviewWarnings: false
    )
    #expect(
      emptyNameResult.issues
        == [.invalidResponsibleParty(.emptyCustomName)]
    )

    var longNameDraft = emptyNameDraft
    longNameDraft.responsibleParty = .custom(String(repeating: "家", count: 81))
    let longNameItem = ActionExportPreviewItem(
      actionID: emptyNameItem.actionID,
      category: emptyNameItem.category,
      sourceDocumentHash: emptyNameItem.sourceDocumentHash,
      evidence: emptyNameItem.evidence,
      confidence: emptyNameItem.confidence,
      needsReview: emptyNameItem.needsReview,
      draft: longNameDraft,
      destination: emptyNameItem.destination
    )
    let longNameResult = ActionExportRequestBuilder.build(
      from: longNameItem,
      includeResponsiblePartyInNotes: false,
      acknowledgesReviewWarnings: false
    )
    #expect(
      longNameResult.issues
        == [.invalidResponsibleParty(.customNameTooLong(maximum: 80))]
    )
  }

  @Test func defaultEvidenceDetailIsNotWrittenToAppleNotes() throws {
    let evidenceText = "Sensitive source sentence"
    let action = try makeAction(
      id: "source-detail",
      category: .appointment,
      dateTime: ActionDateTime(year: 2026, month: 8, day: 15),
      title: "Follow-up appointment",
      detail: evidenceText,
      evidenceText: evidenceText
    )

    let request = try makeExportRequest(action: action)

    #expect(request.notes?.contains(evidenceText) != true)
    #expect(
      !String(decoding: request.markerCanonicalPayload, as: UTF8.self)
        .contains(evidenceText)
    )
  }

  @Test func explicitlyEditedDetailMayBeWrittenToAppleNotes() throws {
    let evidenceText = "Sensitive source sentence"
    let action = try makeAction(
      id: "edited-detail",
      category: .appointment,
      dateTime: ActionDateTime(year: 2026, month: 8, day: 15),
      title: "Follow-up appointment",
      detail: evidenceText,
      evidenceText: evidenceText
    )
    var draft = ActionDraft(action: action)
    draft.detail = "Use the east entrance"

    let request = try makeExportRequest(action: action, draft: draft)

    #expect(request.notes?.contains("Use the east entrance") == true)
    #expect(request.notes?.contains(evidenceText) != true)
  }

  @Test func localizedExportCopyDoesNotChangeTheDuplicateFingerprint() throws {
    let action = try makeAction(
      id: "localized-export",
      category: .requiredItem,
      title: "Bring",
      detail: "Bring your appointment letter",
      evidenceText: "Bring your appointment letter"
    )
    var draft = ActionDraft(action: action)
    draft.items = ["Appointment letter"]
    draft.location = "Clinic A"
    draft.contact = "2123 4567"
    draft.responsibleParty = .familyOrCaregiver
    let item = try #require(
      ActionExportPreviewBuilder.build(
        sourceDocumentHash: "source-hash",
        actions: [action],
        drafts: [draft],
        confirmedActionIDs: [action.id]
      ).items.first
    )

    let english = try #require(
      ActionExportRequestBuilder.build(
        from: item,
        includeResponsiblePartyInNotes: true,
        acknowledgesReviewWarnings: true,
        presentation: .init(
          title: "Required item",
          bringLabel: "Bring",
          contactLabel: "Contact",
          locationLabel: "Location",
          responsibleLabel: "Responsible"
        )
      ).request
    )
    let traditionalChinese = try #require(
      ActionExportRequestBuilder.build(
        from: item,
        includeResponsiblePartyInNotes: true,
        acknowledgesReviewWarnings: true,
        presentation: .init(
          title: "要帶物品",
          bringLabel: "要帶",
          contactLabel: "聯絡",
          locationLabel: "地點",
          responsibleLabel: "負責人",
          meLabel: "我",
          familyOrCaregiverLabel: "家人或照顧者",
          separator: "："
        )
      ).request
    )

    #expect(english.title == "Required item")
    #expect(traditionalChinese.title == "要帶物品")
    #expect(english.notes?.contains("Bring:") == true)
    #expect(traditionalChinese.notes?.contains("要帶：") == true)
    #expect(traditionalChinese.notes?.contains("地點：Clinic A") == true)
    #expect(traditionalChinese.notes?.contains("負責人：") == true)
    #expect(english.markerCanonicalPayload == traditionalChinese.markerCanonicalPayload)
  }

  @Test func canonicalMarkerMaterialIsStableAndOmitsRawEvidence() throws {
    let first = try makeAction(
      id: "first-id",
      category: .appointment,
      dateTime: ActionDateTime(year: 2026, month: 8, day: 15, hour: 9),
      documentID: UUID(uuidString: "00000000-0000-0000-0000-000000000081")!,
      title: "Follow-up appointment",
      detail: "Attend clinic",
      evidenceText: "Sensitive source quote"
    )
    let second = try makeAction(
      id: "second-id",
      category: .appointment,
      dateTime: ActionDateTime(year: 2026, month: 8, day: 15, hour: 9),
      documentID: UUID(uuidString: "00000000-0000-0000-0000-000000000082")!,
      title: "Follow-up appointment",
      detail: "Attend clinic",
      evidenceText: "Sensitive source quote"
    )
    var firstDraft = ActionDraft(action: first)
    var secondDraft = ActionDraft(action: second)
    firstDraft.responsibleParty = .custom("Grandma")
    secondDraft.responsibleParty = .custom("Grandma")

    let firstItem = try #require(
      ActionExportPreviewBuilder.build(
        sourceDocumentHash: "same-source-hash",
        actions: [first],
        drafts: [firstDraft],
        confirmedActionIDs: [first.id]
      ).items.first
    )
    let secondItem = try #require(
      ActionExportPreviewBuilder.build(
        sourceDocumentHash: "same-source-hash",
        actions: [second],
        drafts: [secondDraft],
        confirmedActionIDs: [second.id]
      ).items.first
    )
    let firstRequest = try #require(
      ActionExportRequestBuilder.build(
        from: firstItem,
        includeResponsiblePartyInNotes: false,
        acknowledgesReviewWarnings: false
      ).request
    )
    let secondRequest = try #require(
      ActionExportRequestBuilder.build(
        from: secondItem,
        includeResponsiblePartyInNotes: false,
        acknowledgesReviewWarnings: false
      ).request
    )

    #expect(firstRequest.markerCanonicalPayload == secondRequest.markerCanonicalPayload)
    #expect(firstRequest.notes?.contains("Grandma") != true)
    let material = String(decoding: firstRequest.markerCanonicalPayload, as: UTF8.self)
    #expect(!material.contains("Sensitive source quote"))
    #expect(!material.contains(first.evidence.documentID.uuidString))

    var changedResponsibleDraft = firstDraft
    changedResponsibleDraft.responsibleParty = .me
    let changedResponsibleItem = try #require(
      ActionExportPreviewBuilder.build(
        sourceDocumentHash: "same-source-hash",
        actions: [first],
        drafts: [changedResponsibleDraft],
        confirmedActionIDs: [first.id]
      ).items.first
    )
    let changedResponsibleRequest = try #require(
      ActionExportRequestBuilder.build(
        from: changedResponsibleItem,
        includeResponsiblePartyInNotes: false,
        acknowledgesReviewWarnings: false
      ).request
    )
    #expect(
      changedResponsibleRequest.markerCanonicalPayload
        == firstRequest.markerCanonicalPayload
    )

    let optedInRequest = try #require(
      ActionExportRequestBuilder.build(
        from: firstItem,
        includeResponsiblePartyInNotes: true,
        acknowledgesReviewWarnings: false
      ).request
    )
    #expect(optedInRequest.notes?.contains("Grandma") == true)
    #expect(optedInRequest.markerCanonicalPayload == firstRequest.markerCanonicalPayload)
    #expect(
      !String(decoding: optedInRequest.markerCanonicalPayload, as: UTF8.self).contains("Grandma"))

    var reminderItem = firstItem
    reminderItem.destination = .reminder
    let reminderRequest = try #require(
      ActionExportRequestBuilder.build(
        from: reminderItem,
        includeResponsiblePartyInNotes: false,
        acknowledgesReviewWarnings: false
      ).request
    )
    #expect(reminderRequest.markerCanonicalPayload != firstRequest.markerCanonicalPayload)
  }

  @Test func canonicalMarkerChangesForEachApprovedFingerprintInput() throws {
    let baseAction = try makeAction(
      id: "fingerprint",
      category: .appointment,
      dateTime: ActionDateTime(year: 2026, month: 8, day: 15, hour: 9),
      title: "Follow-up",
      detail: "Attend",
      evidenceText: "AB"
    )
    let changedRuleAction = try makeAction(
      id: "fingerprint",
      category: .appointment,
      dateTime: baseAction.dateTime,
      title: baseAction.title,
      detail: baseAction.detail,
      evidenceText: "AB",
      ruleID: "test.changed-rule"
    )
    let changedRangeAction = try makeAction(
      id: "fingerprint",
      category: .appointment,
      dateTime: baseAction.dateTime,
      title: baseAction.title,
      detail: baseAction.detail,
      evidenceText: "AB",
      rangeLocation: 1,
      rangeLength: 1
    )
    var editedTitleDraft = ActionDraft(action: baseAction)
    editedTitleDraft.title = "Changed title"
    var editedDetailDraft = ActionDraft(action: baseAction)
    editedDetailDraft.detail = "Changed detail"
    var editedDateDraft = ActionDraft(action: baseAction)
    editedDateDraft.dateTime = ActionDateTime(year: 2026, month: 8, day: 16, hour: 10)
    var editedLocationDraft = ActionDraft(action: baseAction)
    editedLocationDraft.location = "Clinic B"
    var editedItemsDraft = ActionDraft(action: baseAction)
    editedItemsDraft.items = ["HKID"]
    var editedContactDraft = ActionDraft(action: baseAction)
    editedContactDraft.contact = "2123 4567"

    let baseRequest = try makeExportRequest(action: baseAction)
    let changedSourceRequest = try makeExportRequest(
      action: baseAction,
      sourceDocumentHash: "changed-source-hash"
    )
    let changedRuleRequest = try makeExportRequest(action: changedRuleAction)
    let changedRangeRequest = try makeExportRequest(action: changedRangeAction)
    let editedTitleRequest = try makeExportRequest(
      action: baseAction,
      draft: editedTitleDraft
    )
    let editedDetailRequest = try makeExportRequest(
      action: baseAction,
      draft: editedDetailDraft
    )
    let editedDateRequest = try makeExportRequest(
      action: baseAction,
      draft: editedDateDraft
    )
    let editedLocationRequest = try makeExportRequest(
      action: baseAction,
      draft: editedLocationDraft
    )
    let editedItemsRequest = try makeExportRequest(
      action: baseAction,
      draft: editedItemsDraft
    )
    let editedContactRequest = try makeExportRequest(
      action: baseAction,
      draft: editedContactDraft
    )
    let changedDestinationRequest = try makeExportRequest(
      action: baseAction,
      destination: .reminder
    )

    let payloads = [
      baseRequest,
      changedSourceRequest,
      changedRuleRequest,
      changedRangeRequest,
      editedTitleRequest,
      editedDetailRequest,
      editedDateRequest,
      editedLocationRequest,
      editedItemsRequest,
      editedContactRequest,
      changedDestinationRequest,
    ].map(\.markerCanonicalPayload)
    #expect(Set(payloads).count == payloads.count)
  }

  @Test func canonicalMarkerEncodingIsAVersionedKnownVector() throws {
    let action = try makeAction(
      id: "vector",
      category: .appointment,
      dateTime: ActionDateTime(year: 2026, month: 8, day: 15, hour: 9),
      title: "vector",
      detail: "vector"
    )
    let item = try #require(
      ActionExportPreviewBuilder.build(
        sourceDocumentHash: "source-hash",
        actions: [action],
        drafts: [ActionDraft(action: action)],
        confirmedActionIDs: [action.id]
      ).items.first
    )
    let request = try #require(
      ActionExportRequestBuilder.build(
        from: item,
        includeResponsiblePartyInNotes: false,
        acknowledgesReviewWarnings: false
      ).request
    )
    let expected =
      "version=s1:1|sourceHash=s11:source-hash|rule=s9:test.rule|rangeLocation=s1:0|rangeLength=s1:1|destination=s8:calendar|title=s6:vector|detail=s6:vector|dateTime=s16:2026-08-15T09:00|location=n|itemCount=s1:0|items=s0:|contact=n|notes=n"

    #expect(String(decoding: request.markerCanonicalPayload, as: UTF8.self) == expected)
  }

  @Test func canonicalMarkerNormalizesEditableTextAndCollectionItems() throws {
    let action = try makeAction(
      id: "normalized",
      category: .appointment,
      dateTime: ActionDateTime(year: 2026, month: 8, day: 15, hour: 9),
      title: "Follow-up",
      detail: "Attend"
    )
    var paddedDraft = ActionDraft(action: action)
    paddedDraft.title = "  Follow-up  "
    paddedDraft.detail = "  Attend  "
    paddedDraft.location = "  Clinic A  "
    paddedDraft.items = ["  HKID  ", "  ", "Appointment letter"]
    paddedDraft.contact = "  2123 4567  "
    var normalizedDraft = ActionDraft(action: action)
    normalizedDraft.location = "Clinic A"
    normalizedDraft.items = ["HKID", "Appointment letter"]
    normalizedDraft.contact = "2123 4567"

    let paddedItem = try #require(
      ActionExportPreviewBuilder.build(
        sourceDocumentHash: "source-hash",
        actions: [action],
        drafts: [paddedDraft],
        confirmedActionIDs: [action.id]
      ).items.first
    )
    let normalizedItem = try #require(
      ActionExportPreviewBuilder.build(
        sourceDocumentHash: "source-hash",
        actions: [action],
        drafts: [normalizedDraft],
        confirmedActionIDs: [action.id]
      ).items.first
    )
    let paddedRequest = try #require(
      ActionExportRequestBuilder.build(
        from: paddedItem,
        includeResponsiblePartyInNotes: false,
        acknowledgesReviewWarnings: false
      ).request
    )
    let normalizedRequest = try #require(
      ActionExportRequestBuilder.build(
        from: normalizedItem,
        includeResponsiblePartyInNotes: false,
        acknowledgesReviewWarnings: false
      ).request
    )

    #expect(paddedRequest.title == normalizedRequest.title)
    #expect(paddedRequest.location == normalizedRequest.location)
    #expect(paddedRequest.notes == normalizedRequest.notes)
    #expect(paddedRequest.markerCanonicalPayload == normalizedRequest.markerCanonicalPayload)
  }

  @Test func canonicalMarkerNormalizesUnicodeAndEmptyOptionalText() throws {
    let action = try makeAction(
      id: "unicode-normalized",
      category: .appointment,
      dateTime: ActionDateTime(year: 2026, month: 8, day: 15),
      title: "Follow-up",
      detail: "Attend"
    )
    var decomposedDraft = ActionDraft(action: action)
    decomposedDraft.title = "Cafe\u{301} follow-up"
    decomposedDraft.detail = "Bring re\u{301}sume\u{301}"
    decomposedDraft.location = " \n "
    decomposedDraft.items = [" \t "]
    decomposedDraft.contact = "  "
    var precomposedDraft = ActionDraft(action: action)
    precomposedDraft.title = "Café follow-up"
    precomposedDraft.detail = "Bring résumé"
    precomposedDraft.location = nil
    precomposedDraft.items = []
    precomposedDraft.contact = nil

    let decomposedItem = try #require(
      ActionExportPreviewBuilder.build(
        sourceDocumentHash: "source-hash",
        actions: [action],
        drafts: [decomposedDraft],
        confirmedActionIDs: [action.id]
      ).items.first
    )
    let precomposedItem = try #require(
      ActionExportPreviewBuilder.build(
        sourceDocumentHash: "source-hash",
        actions: [action],
        drafts: [precomposedDraft],
        confirmedActionIDs: [action.id]
      ).items.first
    )
    let decomposedRequest = try #require(
      ActionExportRequestBuilder.build(
        from: decomposedItem,
        includeResponsiblePartyInNotes: false,
        acknowledgesReviewWarnings: false
      ).request
    )
    let precomposedRequest = try #require(
      ActionExportRequestBuilder.build(
        from: precomposedItem,
        includeResponsiblePartyInNotes: false,
        acknowledgesReviewWarnings: false
      ).request
    )

    #expect(decomposedRequest.location == nil)
    #expect(decomposedRequest.notes == precomposedRequest.notes)
    #expect(decomposedRequest.markerCanonicalPayload == precomposedRequest.markerCanonicalPayload)
  }

  @Test func partialBatchReceiptContainsOnlyItemsCreatedByThisExport() throws {
    let operationID = UUID(uuidString: "00000000-0000-0000-0000-000000000089")!
    let createdReceipt = ExportReceiptItem(
      actionID: "created",
      destination: .calendar,
      calendarItemIdentifier: "event-id",
      markerURLString: "carebrief://export/v1/calendar/digest",
      dateTime: ActionDateTime(year: 2026, month: 8, day: 15, hour: 9)
    )
    let batch = ActionExportBatchResult(
      operationID: operationID,
      results: [
        ActionExportItemResult(actionID: "created", outcome: .created(createdReceipt)),
        ActionExportItemResult(actionID: "duplicate", outcome: .alreadyAdded),
        ActionExportItemResult(actionID: "failed", outcome: .failed(.saveFailed)),
      ]
    )

    let receipt = try #require(batch.receipt)
    #expect(receipt.operationID == operationID)
    #expect(receipt.items == [createdReceipt])
    #expect(batch.results.count == 3)
  }
}

private func makeAction(
  id: String,
  category: ActionCategory,
  dateTime: ActionDateTime? = nil,
  documentID: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000081")!,
  title: String? = nil,
  detail: String? = nil,
  evidenceText: String = "A",
  needsReview: Bool = false,
  ruleID: String = "test.rule",
  rangeLocation: Int = 0,
  rangeLength: Int? = nil
) throws -> ActionCard {
  let resolvedRangeLength = rangeLength ?? (evidenceText as NSString).length
  let range = try #require(
    UTF16TextRange(location: rangeLocation, length: resolvedRangeLength)
  )
  let evidence = SourceEvidence(
    documentID: documentID,
    range: range,
    text: evidenceText,
    ruleID: ruleID
  )
  return ActionCard(
    id: id,
    category: category,
    title: title ?? id,
    detail: detail ?? id,
    dateTime: dateTime,
    evidence: evidence,
    confidence: .high,
    needsReview: needsReview
  )
}

private func makeExportRequest(
  action: ActionCard,
  sourceDocumentHash: String = "source-hash",
  draft: ActionDraft? = nil,
  destination: ActionExportDestination = .calendar
) throws -> ActionExportRequest {
  var item = try #require(
    ActionExportPreviewBuilder.build(
      sourceDocumentHash: sourceDocumentHash,
      actions: [action],
      drafts: [draft ?? ActionDraft(action: action)],
      confirmedActionIDs: [action.id]
    ).items.first
  )
  item.destination = destination
  return try #require(
    ActionExportRequestBuilder.build(
      from: item,
      includeResponsiblePartyInNotes: false,
      acknowledgesReviewWarnings: true
    ).request
  )
}

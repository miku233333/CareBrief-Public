import CareBriefAppSupport
import CareBriefCore
import Foundation
import Testing

@testable import CareBrief

@MainActor
@Suite struct CareBriefViewModelExportTests {
  @Test func successfulExportAnnouncesTraditionalChineseResult() async throws {
    let announcer = RecordingAccessibilityAnnouncer()
    let exporter = makeCreatedExporter { receipt in
      ActionUndoBatchResult(operationID: receipt.operationID, results: [])
    }
    let viewModel = CareBriefViewModel(
      appLanguage: .traditionalChinese,
      exporter: exporter,
      announcer: announcer
    )
    viewModel.loadSample()
    viewModel.extract()
    let action = try #require(viewModel.actions.first)
    viewModel.setConfirmation(true, forActionID: action.id)
    viewModel.prepareExportPreview()

    await viewModel.addPreparedActions(acknowledgesReviewWarnings: true)

    #expect(announcer.messages == ["加入完成：新增 1 項，已有 0 項，失敗 0 項。"])
  }

  @Test func successfulExportAnnouncesEnglishResult() async throws {
    let announcer = RecordingAccessibilityAnnouncer()
    let exporter = makeCreatedExporter { receipt in
      ActionUndoBatchResult(operationID: receipt.operationID, results: [])
    }
    let viewModel = CareBriefViewModel(
      appLanguage: .english,
      exporter: exporter,
      announcer: announcer
    )
    viewModel.loadSample()
    viewModel.extract()
    let action = try #require(viewModel.actions.first)
    viewModel.setConfirmation(true, forActionID: action.id)
    viewModel.prepareExportPreview()

    await viewModel.addPreparedActions(acknowledgesReviewWarnings: true)

    #expect(announcer.messages == ["Add finished. 1 added, 0 already added, 0 failed."])
  }

  @Test func duplicateExportAnnouncesTraditionalChineseResult() async throws {
    let announcer = RecordingAccessibilityAnnouncer()
    let exporter = FakeActionExporter(exportOutcome: .alreadyAdded)
    let viewModel = CareBriefViewModel(
      appLanguage: .traditionalChinese,
      exporter: exporter,
      announcer: announcer
    )
    viewModel.loadSample()
    viewModel.extract()
    let action = try #require(viewModel.actions.first)
    viewModel.setConfirmation(true, forActionID: action.id)
    viewModel.prepareExportPreview()

    await viewModel.addPreparedActions(acknowledgesReviewWarnings: true)

    #expect(announcer.messages == ["加入完成：新增 0 項，已有 1 項，失敗 0 項。"])
  }

  @Test func duplicateExportAnnouncesEnglishResult() async throws {
    let announcer = RecordingAccessibilityAnnouncer()
    let exporter = FakeActionExporter(exportOutcome: .alreadyAdded)
    let viewModel = CareBriefViewModel(
      appLanguage: .english,
      exporter: exporter,
      announcer: announcer
    )
    viewModel.loadSample()
    viewModel.extract()
    let action = try #require(viewModel.actions.first)
    viewModel.setConfirmation(true, forActionID: action.id)
    viewModel.prepareExportPreview()

    await viewModel.addPreparedActions(acknowledgesReviewWarnings: true)

    #expect(announcer.messages == ["Add finished. 0 added, 1 already added, 0 failed."])
  }

  @Test func partialExportFailureAnnouncesTraditionalChineseResult() async throws {
    let announcer = RecordingAccessibilityAnnouncer()
    let exporter = makePartialFailureExporter()
    let viewModel = CareBriefViewModel(
      appLanguage: .traditionalChinese,
      exporter: exporter,
      announcer: announcer
    )
    viewModel.loadSample()
    viewModel.extract()
    let actions = Array(viewModel.actions.prefix(2))
    #expect(actions.count == 2)
    for action in actions {
      viewModel.setConfirmation(true, forActionID: action.id)
    }
    viewModel.prepareExportPreview()

    await viewModel.addPreparedActions(acknowledgesReviewWarnings: true)

    #expect(announcer.messages == ["加入完成：新增 1 項，已有 0 項，失敗 1 項。"])
  }

  @Test func partialExportFailureAnnouncesEnglishResult() async throws {
    let announcer = RecordingAccessibilityAnnouncer()
    let exporter = makePartialFailureExporter()
    let viewModel = CareBriefViewModel(
      appLanguage: .english,
      exporter: exporter,
      announcer: announcer
    )
    viewModel.loadSample()
    viewModel.extract()
    let actions = Array(viewModel.actions.prefix(2))
    #expect(actions.count == 2)
    for action in actions {
      viewModel.setConfirmation(true, forActionID: action.id)
    }
    viewModel.prepareExportPreview()

    await viewModel.addPreparedActions(acknowledgesReviewWarnings: true)

    #expect(announcer.messages == ["Add finished. 1 added, 0 already added, 1 failed."])
  }

  @Test func successfulUndoAnnouncesTraditionalChineseResult() async throws {
    let announcer = RecordingAccessibilityAnnouncer()
    let exporter = makeCreatedExporter { receipt in
      ActionUndoBatchResult(
        operationID: receipt.operationID,
        results: receipt.items.map {
          ActionUndoItemResult(actionID: $0.actionID, outcome: .removed)
        }
      )
    }
    let viewModel = CareBriefViewModel(
      appLanguage: .traditionalChinese,
      exporter: exporter,
      announcer: announcer
    )
    viewModel.loadSample()
    viewModel.extract()
    let action = try #require(viewModel.actions.first)
    viewModel.setConfirmation(true, forActionID: action.id)
    viewModel.prepareExportPreview()
    await viewModel.addPreparedActions(acknowledgesReviewWarnings: true)

    await viewModel.undoLatestExport()

    #expect(
      announcer.messages == [
        "加入完成：新增 1 項，已有 0 項，失敗 0 項。",
        "Undo 完成：移除 1 項，原已移除 0 項，失敗 0 項。",
      ]
    )
  }

  @Test func alreadyRemovedUndoAnnouncesEnglishResultSeparately() async throws {
    let announcer = RecordingAccessibilityAnnouncer()
    let exporter = makeCreatedExporter { receipt in
      ActionUndoBatchResult(
        operationID: receipt.operationID,
        results: receipt.items.map {
          ActionUndoItemResult(actionID: $0.actionID, outcome: .alreadyRemoved)
        }
      )
    }
    let viewModel = CareBriefViewModel(
      appLanguage: .english,
      exporter: exporter,
      announcer: announcer
    )
    viewModel.loadSample()
    viewModel.extract()
    let action = try #require(viewModel.actions.first)
    viewModel.setConfirmation(true, forActionID: action.id)
    viewModel.prepareExportPreview()
    await viewModel.addPreparedActions(acknowledgesReviewWarnings: true)

    await viewModel.undoLatestExport()

    #expect(
      announcer.messages == [
        "Add finished. 1 added, 0 already added, 0 failed.",
        "Undo finished. 0 removed, 1 already removed, 0 failed.",
      ]
    )
  }

  @Test func permissionFailureKeepsPreviewAndDoesNotCreateUndoReceipt() async throws {
    let exporter = FakeActionExporter(exportOutcome: .failed(.permissionDenied))
    let viewModel = CareBriefViewModel(exporter: exporter)
    viewModel.loadSample()
    viewModel.extract()
    let action = try #require(viewModel.actions.first)
    viewModel.setConfirmation(true, forActionID: action.id)
    viewModel.prepareExportPreview()

    await viewModel.addPreparedActions(acknowledgesReviewWarnings: true)

    #expect(exporter.exportedRequests.map(\.actionID) == [action.id])
    #expect(viewModel.exportPreview != nil)
    #expect(viewModel.latestExportReceipt == nil)
    #expect(viewModel.exportResult?.results.first?.outcome == .failed(.permissionDenied))
  }

  @Test func partialSuccessPreservesCreatedReceiptAndUndoConsumesIt() async throws {
    let operationID = UUID(uuidString: "00000000-0000-0000-0000-000000000091")!
    let exporter = FakeActionExporter(
      exportHandler: { requests in
        let created = ExportReceiptItem(
          actionID: requests[0].actionID,
          destination: requests[0].destination,
          calendarItemIdentifier: "created-id",
          markerURLString: "carebrief://export/v1/calendar/created",
          dateTime: requests[0].dateTime
        )
        return ActionExportBatchResult(
          operationID: operationID,
          results: [
            ActionExportItemResult(
              actionID: requests[0].actionID,
              outcome: .created(created)
            ),
            ActionExportItemResult(
              actionID: requests[1].actionID,
              outcome: .failed(.saveFailed)
            ),
          ]
        )
      },
      undoHandler: { receipt in
        ActionUndoBatchResult(
          operationID: receipt.operationID,
          results: receipt.items.map {
            ActionUndoItemResult(actionID: $0.actionID, outcome: .removed)
          }
        )
      }
    )
    let viewModel = CareBriefViewModel(exporter: exporter)
    viewModel.loadSample()
    viewModel.extract()
    let actions = Array(viewModel.actions.prefix(2))
    #expect(actions.count == 2)
    for action in actions {
      viewModel.setConfirmation(true, forActionID: action.id)
    }
    viewModel.prepareExportPreview()

    await viewModel.addPreparedActions(acknowledgesReviewWarnings: true)

    let receipt = try #require(viewModel.latestExportReceipt)
    #expect(receipt.operationID == operationID)
    #expect(receipt.items.map(\.actionID) == [actions[0].id])
    #expect(viewModel.exportResult?.results.count == 2)

    viewModel.prepareExportPreview()
    #expect(viewModel.latestExportReceipt == receipt)

    await viewModel.undoLatestExport()

    #expect(exporter.undoneReceipts == [receipt])
    #expect(viewModel.latestExportReceipt == nil)
    #expect(viewModel.undoResult?.results.first?.outcome == .removed)
  }

  @Test func cryptoKitDigestMatchesThePublishedSHA256Vector() {
    #expect(
      CareBriefSHA256.hexDigest(Data("abc".utf8))
        == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    )
  }

  @Test func markerURLMatchesTheVersionedCanonicalVector() {
    let canonical =
      "version=s1:1|sourceHash=s11:source-hash|rule=s9:test.rule|rangeLocation=s1:0|rangeLength=s1:1|destination=s8:calendar|title=s6:vector|detail=s6:vector|dateTime=s16:2026-08-15T09:00|location=n|itemCount=s1:0|items=s0:|contact=n|notes=n"
    let request = ActionExportRequest(
      actionID: "vector",
      destination: .calendar,
      title: "vector",
      notes: nil,
      dateTime: ActionDateTime(year: 2026, month: 8, day: 15, hour: 9),
      location: nil,
      isAllDay: false,
      durationMinutes: 60,
      markerCanonicalPayload: Data(canonical.utf8)
    )

    #expect(
      CareBriefSHA256.markerURL(for: request)?.absoluteString
        == "carebrief://export/v1/calendar/cfcb0999aa2786f0b7df11c4ee79fae936e7d88d9fa29ea1acf532a040ce41d6"
    )
  }

  @Test func duplicateResultKeepsTheLatestCreatedReceiptAvailableForUndo() async throws {
    var exportCallCount = 0
    let exporter = FakeActionExporter(
      exportHandler: { requests in
        exportCallCount += 1
        if exportCallCount == 1 {
          let request = requests[0]
          let receipt = ExportReceiptItem(
            actionID: request.actionID,
            destination: request.destination,
            calendarItemIdentifier: "created-id",
            markerURLString: "carebrief://export/v1/calendar/created",
            dateTime: request.dateTime
          )
          return ActionExportBatchResult(
            results: [
              ActionExportItemResult(
                actionID: request.actionID,
                outcome: .created(receipt)
              )
            ]
          )
        }
        return ActionExportBatchResult(
          results: requests.map {
            ActionExportItemResult(actionID: $0.actionID, outcome: .alreadyAdded)
          }
        )
      },
      undoHandler: { receipt in
        ActionUndoBatchResult(
          operationID: receipt.operationID,
          results: receipt.items.map {
            ActionUndoItemResult(actionID: $0.actionID, outcome: .removed)
          }
        )
      }
    )
    let viewModel = CareBriefViewModel(exporter: exporter)
    viewModel.loadSample()
    viewModel.extract()
    let action = try #require(viewModel.actions.first)
    viewModel.setConfirmation(true, forActionID: action.id)
    viewModel.prepareExportPreview()

    await viewModel.addPreparedActions(acknowledgesReviewWarnings: true)
    let createdReceipt = try #require(viewModel.latestExportReceipt)
    viewModel.prepareExportPreview()
    await viewModel.addPreparedActions(acknowledgesReviewWarnings: true)

    #expect(viewModel.exportResult?.results.first?.outcome == .alreadyAdded)
    #expect(viewModel.latestExportReceipt == createdReceipt)
    #expect(exportCallCount == 2)
  }

  @Test func successiveCreatedBatchesRemainUndoableNewestFirst() async throws {
    var exportCallCount = 0
    let exporter = FakeActionExporter(
      exportHandler: { requests in
        exportCallCount += 1
        let results = requests.map { request in
          if exportCallCount == 2, request.actionID == requests[0].actionID {
            return ActionExportItemResult(
              actionID: request.actionID,
              outcome: .alreadyAdded
            )
          }
          let receipt = ExportReceiptItem(
            actionID: request.actionID,
            destination: request.destination,
            calendarItemIdentifier: "\(request.actionID)-id",
            markerURLString:
              "carebrief://export/v1/\(request.destination.rawValue)/\(request.actionID)",
            dateTime: request.dateTime
          )
          return ActionExportItemResult(
            actionID: request.actionID,
            outcome: .created(receipt)
          )
        }
        return ActionExportBatchResult(results: results)
      },
      undoHandler: { receipt in
        ActionUndoBatchResult(
          operationID: receipt.operationID,
          results: receipt.items.map {
            ActionUndoItemResult(actionID: $0.actionID, outcome: .removed)
          }
        )
      }
    )
    let viewModel = CareBriefViewModel(exporter: exporter)
    viewModel.loadSample()
    viewModel.extract()
    let actions = Array(viewModel.actions.prefix(2))
    #expect(actions.count == 2)

    viewModel.setConfirmation(true, forActionID: actions[0].id)
    viewModel.prepareExportPreview()
    await viewModel.addPreparedActions(acknowledgesReviewWarnings: true)
    let firstReceipt = try #require(viewModel.latestExportReceipt)

    viewModel.setConfirmation(true, forActionID: actions[1].id)
    viewModel.prepareExportPreview()
    await viewModel.addPreparedActions(acknowledgesReviewWarnings: true)
    let secondReceipt = try #require(viewModel.latestExportReceipt)
    #expect(secondReceipt.items.map(\.actionID) == [actions[1].id])

    await viewModel.undoLatestExport()
    #expect(viewModel.latestExportReceipt == firstReceipt)
    await viewModel.undoLatestExport()
    #expect(viewModel.latestExportReceipt == nil)
    #expect(exporter.undoneReceipts == [secondReceipt, firstReceipt])
  }

  @Test func noOpDraftSaveAndMalformedUndoDoNotDiscardReviewOrReceipt() async throws {
    let exporter = FakeActionExporter(
      exportHandler: { requests in
        let request = requests[0]
        let receipt = ExportReceiptItem(
          actionID: request.actionID,
          destination: request.destination,
          calendarItemIdentifier: "created-id",
          markerURLString: "carebrief://export/v1/calendar/created",
          dateTime: request.dateTime
        )
        return ActionExportBatchResult(
          results: [
            ActionExportItemResult(
              actionID: request.actionID,
              outcome: .created(receipt)
            )
          ]
        )
      },
      undoHandler: { receipt in
        ActionUndoBatchResult(operationID: receipt.operationID, results: [])
      }
    )
    let viewModel = CareBriefViewModel(exporter: exporter)
    viewModel.loadSample()
    viewModel.extract()
    let action = try #require(viewModel.actions.first)
    viewModel.setConfirmation(true, forActionID: action.id)
    viewModel.prepareExportPreview()
    await viewModel.addPreparedActions(acknowledgesReviewWarnings: true)
    let receipt = try #require(viewModel.latestExportReceipt)
    let preview = try #require(viewModel.exportPreview)
    let unchangedDraft = try #require(viewModel.draft(forActionID: action.id))

    viewModel.updateDraft(unchangedDraft)
    #expect(viewModel.isConfirmed(actionID: action.id))
    #expect(viewModel.exportPreview == preview)
    #expect(viewModel.latestExportReceipt == receipt)

    await viewModel.undoLatestExport()
    #expect(viewModel.latestExportReceipt == receipt)

    var changedDraft = unchangedDraft
    changedDraft.title += " updated"
    viewModel.updateDraft(changedDraft)
    #expect(!viewModel.isConfirmed(actionID: action.id))
    #expect(viewModel.latestExportReceipt == receipt)
    viewModel.prepareExportPreview()
    #expect(viewModel.exportPreview?.items.isEmpty == true)
  }

  @Test func failedUndoKeepsDraftConfirmationAndReceiptForRetry() async throws {
    var undoCallCount = 0
    let exporter = makeCreatedExporter { receipt in
      undoCallCount += 1
      let outcome: ActionUndoItemOutcome =
        undoCallCount == 1 ? .failed(.removeFailed) : .removed
      return ActionUndoBatchResult(
        operationID: receipt.operationID,
        results: receipt.items.map {
          ActionUndoItemResult(actionID: $0.actionID, outcome: outcome)
        }
      )
    }
    let viewModel = CareBriefViewModel(exporter: exporter)
    viewModel.loadSample()
    viewModel.extract()
    let action = try #require(viewModel.actions.first)
    viewModel.setConfirmation(true, forActionID: action.id)
    let draft = try #require(viewModel.draft(forActionID: action.id))
    viewModel.prepareExportPreview()
    await viewModel.addPreparedActions(acknowledgesReviewWarnings: true)
    let receipt = try #require(viewModel.latestExportReceipt)

    await viewModel.undoLatestExport()

    #expect(viewModel.undoResult?.results.first?.outcome == .failed(.removeFailed))
    #expect(viewModel.latestExportReceipt == receipt)
    #expect(viewModel.draft(forActionID: action.id) == draft)
    #expect(viewModel.isConfirmed(actionID: action.id))

    await viewModel.undoLatestExport()

    #expect(viewModel.undoResult?.results.first?.outcome == .removed)
    #expect(viewModel.latestExportReceipt == nil)
    #expect(exporter.undoneReceipts == [receipt, receipt])
  }

  @Test func mismatchedUndoOperationDoesNotDiscardReceipt() async throws {
    let unexpectedOperationID = UUID(
      uuidString: "00000000-0000-0000-0000-000000000092"
    )!
    let exporter = makeCreatedExporter { receipt in
      ActionUndoBatchResult(
        operationID: unexpectedOperationID,
        results: receipt.items.map {
          ActionUndoItemResult(actionID: $0.actionID, outcome: .removed)
        }
      )
    }
    let viewModel = CareBriefViewModel(exporter: exporter)
    viewModel.loadSample()
    viewModel.extract()
    let action = try #require(viewModel.actions.first)
    viewModel.setConfirmation(true, forActionID: action.id)
    viewModel.prepareExportPreview()
    await viewModel.addPreparedActions(acknowledgesReviewWarnings: true)
    let receipt = try #require(viewModel.latestExportReceipt)

    await viewModel.undoLatestExport()

    #expect(viewModel.latestExportReceipt == receipt)
    #expect(viewModel.undoResult?.operationID == receipt.operationID)
    #expect(
      viewModel.undoResult?.results.first?.outcome
        == .failed(.invalidExporterResult)
    )
  }

  @Test func externallyDeletedItemKeepsDraftAndReceiptWithSafeError() async throws {
    let exporter = makeCreatedExporter { receipt in
      ActionUndoBatchResult(
        operationID: receipt.operationID,
        results: receipt.items.map {
          ActionUndoItemResult(
            actionID: $0.actionID,
            outcome: .failed(.itemNotFound)
          )
        }
      )
    }
    let viewModel = CareBriefViewModel(exporter: exporter)
    viewModel.loadSample()
    viewModel.extract()
    let action = try #require(viewModel.actions.first)
    viewModel.setConfirmation(true, forActionID: action.id)
    let draft = try #require(viewModel.draft(forActionID: action.id))
    viewModel.prepareExportPreview()
    await viewModel.addPreparedActions(acknowledgesReviewWarnings: true)
    let receipt = try #require(viewModel.latestExportReceipt)

    await viewModel.undoLatestExport()

    #expect(viewModel.undoResult?.results.first?.outcome == .failed(.itemNotFound))
    #expect(viewModel.latestExportReceipt == receipt)
    #expect(viewModel.draft(forActionID: action.id) == draft)
    #expect(viewModel.isConfirmed(actionID: action.id))
  }

  @Test func manualInputChangeClearsAllExportStateWithoutDeletingItems() async throws {
    let exporter = makeCreatedExporter { receipt in
      ActionUndoBatchResult(operationID: receipt.operationID, results: [])
    }
    let viewModel = CareBriefViewModel(exporter: exporter)
    viewModel.loadSample()
    viewModel.extract()
    let action = try #require(viewModel.actions.first)
    viewModel.setConfirmation(true, forActionID: action.id)
    viewModel.prepareExportPreview()
    await viewModel.addPreparedActions(acknowledgesReviewWarnings: true)
    #expect(viewModel.latestExportReceipt != nil)

    viewModel.updateInput("新的覆診通知")

    expectExportStateIsReset(viewModel)
    #expect(viewModel.inputText == "新的覆診通知")
    #expect(viewModel.actions.isEmpty)
    #expect(exporter.undoneReceipts.isEmpty)
  }

  @Test func reextractClearsAllExportStateWithoutDeletingItems() async throws {
    let exporter = makeCreatedExporter { receipt in
      ActionUndoBatchResult(operationID: receipt.operationID, results: [])
    }
    let viewModel = CareBriefViewModel(exporter: exporter)
    viewModel.loadSample()
    viewModel.extract()
    let action = try #require(viewModel.actions.first)
    viewModel.setConfirmation(true, forActionID: action.id)
    viewModel.prepareExportPreview()
    await viewModel.addPreparedActions(acknowledgesReviewWarnings: true)
    #expect(viewModel.latestExportReceipt != nil)

    viewModel.extract()

    expectExportStateIsReset(viewModel)
    #expect(!viewModel.actions.isEmpty)
    #expect(viewModel.reviewState.confirmedActionIDs.isEmpty)
    #expect(exporter.undoneReceipts.isEmpty)
  }

  @Test func clearDocumentClearsAllExportStateWithoutDeletingItems() async throws {
    let exporter = makeCreatedExporter { receipt in
      ActionUndoBatchResult(operationID: receipt.operationID, results: [])
    }
    let viewModel = CareBriefViewModel(exporter: exporter)
    viewModel.loadSample()
    viewModel.extract()
    let action = try #require(viewModel.actions.first)
    viewModel.setConfirmation(true, forActionID: action.id)
    viewModel.prepareExportPreview()
    await viewModel.addPreparedActions(acknowledgesReviewWarnings: true)
    #expect(viewModel.latestExportReceipt != nil)

    viewModel.clear()

    expectExportStateIsReset(viewModel)
    #expect(viewModel.inputText.isEmpty)
    #expect(viewModel.actions.isEmpty)
    #expect(exporter.undoneReceipts.isEmpty)
  }

  @Test func startingANewOCRClearsOldReviewAndExportStateEvenWhenItFails() async throws {
    let exporter = makeCreatedExporter { receipt in
      ActionUndoBatchResult(operationID: receipt.operationID, results: [])
    }
    let viewModel = CareBriefViewModel(exporter: exporter)
    viewModel.loadSample()
    viewModel.extract()
    let action = try #require(viewModel.actions.first)
    viewModel.setConfirmation(true, forActionID: action.id)
    viewModel.prepareExportPreview()
    await viewModel.addPreparedActions(acknowledgesReviewWarnings: true)
    let previousInput = viewModel.inputText
    #expect(viewModel.latestExportReceipt != nil)

    viewModel.importDocument {
      throw DocumentImportError.recognitionFailed
    }
    await waitForImportToFinish(viewModel)

    #expect(viewModel.inputText == previousInput)
    #expect(viewModel.actions.isEmpty)
    #expect(viewModel.reviewState.drafts.isEmpty)
    #expect(viewModel.reviewState.confirmedActionIDs.isEmpty)
    expectExportStateIsReset(viewModel)
    #expect(viewModel.importErrorMessage != nil)
    #expect(exporter.undoneReceipts.isEmpty)
  }

  @Test func everyAcceptedOCRAdvancesRevisionEvenWithTheSamePageCount() async throws {
    let viewModel = CareBriefViewModel()
    let first = try makeOCRDocument(text: "第一份文件", pageIndex: 0, sourcePageCount: 1)
    let second = try makeOCRDocument(text: "第二份文件", pageIndex: 0, sourcePageCount: 1)

    viewModel.importDocument { first }
    await waitForImportToFinish(viewModel)
    let firstRevision = viewModel.acceptedImportRevision

    viewModel.importDocument { second }
    await waitForImportToFinish(viewModel)

    #expect(firstRevision == 1)
    #expect(viewModel.acceptedImportRevision == 2)
    #expect(viewModel.inputText == "第二份文件")
  }

  @Test func missingOrDuplicateExporterResultsBecomeSafeFailures() async throws {
    let missingExporter = FakeActionExporter(
      exportHandler: { _ in ActionExportBatchResult(results: []) },
      undoHandler: { receipt in
        ActionUndoBatchResult(operationID: receipt.operationID, results: [])
      }
    )
    let missingViewModel = CareBriefViewModel(exporter: missingExporter)
    missingViewModel.loadSample()
    missingViewModel.extract()
    let missingAction = try #require(missingViewModel.actions.first)
    missingViewModel.setConfirmation(true, forActionID: missingAction.id)
    missingViewModel.prepareExportPreview()
    await missingViewModel.addPreparedActions(acknowledgesReviewWarnings: true)
    #expect(
      missingViewModel.exportResult?.results.first?.outcome
        == .failed(.invalidExporterResult)
    )
    #expect(missingViewModel.latestExportReceipt == nil)

    let duplicateExporter = FakeActionExporter(
      exportHandler: { requests in
        ActionExportBatchResult(
          results: [
            ActionExportItemResult(
              actionID: requests[0].actionID,
              outcome: .alreadyAdded
            ),
            ActionExportItemResult(
              actionID: requests[0].actionID,
              outcome: .alreadyAdded
            ),
          ]
        )
      },
      undoHandler: { receipt in
        ActionUndoBatchResult(operationID: receipt.operationID, results: [])
      }
    )
    let duplicateViewModel = CareBriefViewModel(exporter: duplicateExporter)
    duplicateViewModel.loadSample()
    duplicateViewModel.extract()
    let duplicateAction = try #require(duplicateViewModel.actions.first)
    duplicateViewModel.setConfirmation(true, forActionID: duplicateAction.id)
    duplicateViewModel.prepareExportPreview()
    await duplicateViewModel.addPreparedActions(acknowledgesReviewWarnings: true)
    #expect(
      duplicateViewModel.exportResult?.results.first?.outcome
        == .failed(.invalidExporterResult)
    )
  }
}

@MainActor
private final class RecordingAccessibilityAnnouncer: AccessibilityAnnouncing {
  private(set) var messages: [String] = []

  func announce(_ message: String) {
    messages.append(message)
  }
}

@MainActor
private final class FakeActionExporter: ActionExporting {
  private let exportHandler: ([ActionExportRequest]) -> ActionExportBatchResult
  private let undoHandler: (ExportReceipt) -> ActionUndoBatchResult
  private(set) var exportedRequests: [ActionExportRequest] = []
  private(set) var undoneReceipts: [ExportReceipt] = []

  init(exportOutcome: ActionExportItemOutcome) {
    self.exportHandler = { requests in
      ActionExportBatchResult(
        results: requests.map {
          ActionExportItemResult(actionID: $0.actionID, outcome: exportOutcome)
        }
      )
    }
    self.undoHandler = { receipt in
      ActionUndoBatchResult(operationID: receipt.operationID, results: [])
    }
  }

  init(
    exportHandler: @escaping ([ActionExportRequest]) -> ActionExportBatchResult,
    undoHandler: @escaping (ExportReceipt) -> ActionUndoBatchResult
  ) {
    self.exportHandler = exportHandler
    self.undoHandler = undoHandler
  }

  func export(_ requests: [ActionExportRequest]) async -> ActionExportBatchResult {
    exportedRequests = requests
    return exportHandler(requests)
  }

  func undo(_ receipt: ExportReceipt) async -> ActionUndoBatchResult {
    undoneReceipts.append(receipt)
    return undoHandler(receipt)
  }
}

@MainActor
private func makeCreatedExporter(
  undoHandler: @escaping (ExportReceipt) -> ActionUndoBatchResult
) -> FakeActionExporter {
  FakeActionExporter(
    exportHandler: { requests in
      ActionExportBatchResult(
        results: requests.map { request in
          let receipt = ExportReceiptItem(
            actionID: request.actionID,
            destination: request.destination,
            calendarItemIdentifier: "\(request.actionID)-identifier",
            markerURLString:
              "carebrief://export/v1/\(request.destination.rawValue)/\(request.actionID)",
            dateTime: request.dateTime
          )
          return ActionExportItemResult(
            actionID: request.actionID,
            outcome: .created(receipt)
          )
        }
      )
    },
    undoHandler: undoHandler
  )
}

@MainActor
private func makePartialFailureExporter() -> FakeActionExporter {
  FakeActionExporter(
    exportHandler: { requests in
      let request = requests[0]
      let receipt = ExportReceiptItem(
        actionID: request.actionID,
        destination: request.destination,
        calendarItemIdentifier: "created-id",
        markerURLString: "carebrief://export/v1/calendar/created",
        dateTime: request.dateTime
      )
      return ActionExportBatchResult(
        results: [
          ActionExportItemResult(
            actionID: request.actionID,
            outcome: .created(receipt)
          ),
          ActionExportItemResult(
            actionID: requests[1].actionID,
            outcome: .failed(.saveFailed)
          ),
        ]
      )
    },
    undoHandler: { receipt in
      ActionUndoBatchResult(operationID: receipt.operationID, results: [])
    }
  )
}

@MainActor
private func expectExportStateIsReset(_ viewModel: CareBriefViewModel) {
  #expect(viewModel.exportPreview == nil)
  #expect(viewModel.exportResult == nil)
  #expect(viewModel.latestExportReceipt == nil)
  #expect(viewModel.undoResult == nil)
  #expect(viewModel.exportValidationIssuesByActionID.isEmpty)
  #expect(!viewModel.isExporting)
  #expect(!viewModel.isUndoing)
}

@MainActor
private func waitForImportToFinish(_ viewModel: CareBriefViewModel) async {
  for _ in 0..<100 where viewModel.isImporting {
    await Task.yield()
  }
  #expect(!viewModel.isImporting)
}

private func makeOCRDocument(
  text: String,
  pageIndex: Int,
  sourcePageCount: Int
) throws -> OCRDocument {
  let box = try #require(
    OCRNormalizedRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1)
  )
  let fragment = try #require(
    OCRTextFragment(pageIndex: pageIndex, text: text, boundingBox: box)
  )
  return OCRDocumentAssembler.assemble(
    [fragment],
    sourcePageCount: sourcePageCount
  )
}

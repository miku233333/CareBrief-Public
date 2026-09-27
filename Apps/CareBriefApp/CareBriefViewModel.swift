import CareBriefAppSupport
import CareBriefCore
import Combine
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import VisionKit

@MainActor
final class CareBriefViewModel: ObservableObject {
  static let sampleText = """
    您需於 2026 年 8 月 15 日上午 9 時到威爾斯親王醫院內科門診覆診。
    覆診前禁食 8 小時，請攜帶身份證及覆診紙。
    如有查詢，請致電 2632 2211。
    """

  @Published private(set) var inputText: String
  @Published private(set) var appLanguage: CareBriefAppLanguage
  @Published private(set) var reviewState: DocumentReviewState
  @Published private(set) var importState: DocumentImportState
  @Published private(set) var acceptedImportRevision: Int
  @Published private(set) var exportPreview: ActionExportPreview?
  @Published private(set) var exportResult: ActionExportBatchResult?
  @Published private(set) var latestExportReceipt: ExportReceipt?
  @Published private(set) var undoResult: ActionUndoBatchResult?
  @Published private(set) var exportValidationIssuesByActionID:
    [String: [ActionExportValidationIssue]]
  @Published private(set) var isExporting: Bool
  @Published private(set) var isUndoing: Bool

  private let extractor: any DocumentActionExtracting
  private let textRecognizer: VisionTextRecognizer
  private let exporter: any ActionExporting
  private let accessibilityAnnouncer: any AccessibilityAnnouncing
  private let sampleText: String
  private var importTask: Task<Void, Never>?
  private var exportDestinationOverrides: [String: ActionExportDestination] = [:]
  private var includeResponsiblePartyInNotes = false
  private var outstandingExportReceipts: [ExportReceipt]

  init(
    inputText: String = "",
    language: DocumentLanguage = .unknown,
    appLanguage: CareBriefAppLanguage = CareBriefLanguagePreference.system.resolvedLanguage,
    sampleText: String = CareBriefViewModel.sampleText,
    extractor: any DocumentActionExtracting = RuleBasedActionExtractor(),
    textRecognizer: VisionTextRecognizer = VisionTextRecognizer(),
    exporter: any ActionExporting = EventKitActionExporter(),
    announcer: any AccessibilityAnnouncing = SystemAccessibilityAnnouncer()
  ) {
    self.inputText = inputText
    self.appLanguage = appLanguage
    self.reviewState = DocumentReviewState(inputText: inputText, language: language)
    self.importState = DocumentImportState()
    self.acceptedImportRevision = 0
    self.exportPreview = nil
    self.exportResult = nil
    self.latestExportReceipt = nil
    self.undoResult = nil
    self.exportValidationIssuesByActionID = [:]
    self.isExporting = false
    self.isUndoing = false
    self.outstandingExportReceipts = []
    self.extractor = extractor
    self.textRecognizer = textRecognizer
    self.exporter = exporter
    self.accessibilityAnnouncer = announcer
    self.sampleText = sampleText
  }

  var canExtract: Bool {
    !isImporting
      && inputText.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) != nil
  }

  var hasExtracted: Bool {
    reviewState.extractionResult != nil
  }

  var actions: [ActionCard] {
    reviewState.actions
  }

  var warnings: [String] {
    reviewState.warnings
  }

  var isImporting: Bool {
    importState.status == .processing
  }

  var importErrorMessage: String? {
    guard case .failed(let message) = importState.status else { return nil }
    return CareBriefGeneratedCopy.importError(message, language: appLanguage)
  }

  var hasImportedDocument: Bool {
    importState.latestDocument != nil
  }

  var importSummaryMessage: String? {
    guard let document = importState.latestDocument else { return nil }
    return CareBriefAccessibilityCopy.importSummary(
      pageCount: document.sourcePageCount,
      for: appLanguage
    )
  }

  var importCoverageWarningMessage: String? {
    guard let document = importState.latestDocument,
      !document.pagesWithoutText.isEmpty
    else {
      return nil
    }

    return CareBriefAccessibilityCopy.importCoverageWarning(
      pageNumbers: document.pagesWithoutText.map { $0 + 1 },
      for: appLanguage
    )
  }

  func setAppLanguage(_ language: CareBriefAppLanguage) {
    guard language != appLanguage else { return }
    appLanguage = language
  }

  func updateInput(_ text: String) {
    guard text != inputText else { return }
    abandonImportAndProvenance()
    resetExportState()
    replaceInput(text, language: .unknown)
  }

  func loadSample() {
    abandonImportAndProvenance()
    resetExportState()
    replaceInput(sampleText, language: .traditionalChinese)
  }

  func clear() {
    abandonImportAndProvenance()
    resetExportState()
    inputText = ""
    reviewState.reset()
  }

  func extract() {
    guard canExtract else { return }
    resetExportState()
    var nextState = reviewState
    nextState.extract(using: extractor)
    reviewState = nextState
  }

  func isConfirmed(actionID: String) -> Bool {
    reviewState.isConfirmed(actionID: actionID)
  }

  func setConfirmation(_ isConfirmed: Bool, forActionID actionID: String) {
    guard !isImporting else { return }
    guard reviewState.isConfirmed(actionID: actionID) != isConfirmed else { return }
    var nextState = reviewState
    guard nextState.setConfirmation(isConfirmed, forActionID: actionID) else { return }
    reviewState = nextState
    resetPreparedExportState()
  }

  func draft(forActionID actionID: String) -> ActionDraft? {
    reviewState.draft(forActionID: actionID)
  }

  func isDraftEdited(actionID: String) -> Bool {
    reviewState.isDraftEdited(actionID: actionID)
  }

  func updateDraft(_ draft: ActionDraft) {
    guard reviewState.draft(forActionID: draft.sourceActionID) != draft else { return }
    var nextState = reviewState
    guard nextState.updateDraft(draft) else { return }
    reviewState = nextState
    resetPreparedExportState()
  }

  func prepareExportPreview() {
    guard let sourceDocument = reviewState.sourceDocument else { return }
    exportPreview = ActionExportPreviewBuilder.build(
      sourceDocumentHash: CareBriefSHA256.sourceDocumentHash(sourceDocument.text),
      actions: reviewState.actions,
      drafts: reviewState.drafts,
      confirmedActionIDs: reviewState.confirmedActionIDs,
      destinationOverrides: exportDestinationOverrides,
      includeResponsiblePartyInNotes: includeResponsiblePartyInNotes
    )
    exportResult = nil
    exportValidationIssuesByActionID = [:]
  }

  func setExportDestination(
    _ destination: ActionExportDestination,
    forActionID actionID: String
  ) {
    guard !isExporting, !isUndoing else { return }
    exportDestinationOverrides[actionID] = destination
    prepareExportPreview()
  }

  func setIncludeResponsiblePartyInNotes(_ isIncluded: Bool) {
    guard !isExporting, !isUndoing else { return }
    includeResponsiblePartyInNotes = isIncluded
    prepareExportPreview()
  }

  func addPreparedActions(acknowledgesReviewWarnings: Bool) async {
    guard let preview = exportPreview, !isExporting, !isUndoing else { return }
    var requests: [ActionExportRequest] = []
    var issues: [String: [ActionExportValidationIssue]] = [:]
    for item in preview.items {
      let result = ActionExportRequestBuilder.build(
        from: item,
        includeResponsiblePartyInNotes: preview.includeResponsiblePartyInNotes,
        acknowledgesReviewWarnings: acknowledgesReviewWarnings,
        presentation: CareBriefGeneratedCopy.exportPresentation(
          category: item.category,
          draftTitle: item.draft.title,
          language: appLanguage
        )
      )
      if !result.issues.isEmpty {
        issues[item.actionID] = result.issues
      }
      if let request = result.request {
        requests.append(request)
      }
    }
    exportValidationIssuesByActionID = issues
    guard issues.isEmpty else { return }

    isExporting = true
    defer { isExporting = false }
    let exported = await exporter.export(requests)
    let outcomesByActionID = Dictionary(grouping: exported.results, by: \.actionID)
    let orderedResults = preview.items.map { item in
      if item.destination == .skip {
        return ActionExportItemResult(actionID: item.actionID, outcome: .skipped)
      }
      guard let outcomes = outcomesByActionID[item.actionID], outcomes.count == 1 else {
        return ActionExportItemResult(
          actionID: item.actionID,
          outcome: .failed(.invalidExporterResult)
        )
      }
      return outcomes[0]
    }
    let orderedBatch = ActionExportBatchResult(
      operationID: exported.operationID,
      results: orderedResults
    )
    exportResult = orderedBatch
    if let receipt = orderedBatch.receipt {
      outstandingExportReceipts.append(receipt)
      latestExportReceipt = outstandingExportReceipts.last
    }
    undoResult = nil
    postAccessibilityAnnouncement(exportCompletionAnnouncement(for: orderedBatch))
  }

  func undoLatestExport() async {
    guard let receipt = latestExportReceipt, !isUndoing, !isExporting else { return }
    isUndoing = true
    defer { isUndoing = false }
    let exported = await exporter.undo(receipt)
    let result = validatedUndoResult(exported, for: receipt)
    undoResult = result
    let completedActionIDs = Set(
      result.results.compactMap { item -> String? in
        switch item.outcome {
        case .removed, .alreadyRemoved:
          return item.actionID
        case .failed:
          return nil
        }
      }
    )
    if receipt.items.allSatisfy({ completedActionIDs.contains($0.actionID) }) {
      outstandingExportReceipts.removeAll { $0.operationID == receipt.operationID }
      latestExportReceipt = outstandingExportReceipts.last
    }
    postAccessibilityAnnouncement(undoCompletionAnnouncement(for: result))
  }

  func importPhoto(_ item: PhotosPickerItem) {
    importDocument { [textRecognizer] in
      let data: Data
      do {
        guard let loadedData = try await item.loadTransferable(type: Data.self) else {
          throw DocumentImportError.unreadableImage
        }
        data = loadedData
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        if Task.isCancelled {
          throw CancellationError()
        }
        throw DocumentImportError.unreadableImage
      }

      try Task.checkCancellation()
      let page = try await VisionImagePage.prepare(data: data)

      let fragments = try await textRecognizer.recognize(page: page, pageIndex: 0)
      return OCRDocumentAssembler.assemble(fragments, sourcePageCount: 1)
    }
  }

  func importScan(_ scan: VNDocumentCameraScan) {
    importDocument { [textRecognizer] in
      var fragments: [OCRTextFragment] = []
      for pageIndex in 0..<scan.pageCount {
        try Task.checkCancellation()
        let image = scan.imageOfPage(at: pageIndex)
        guard let source = VisionImageSource(uiImage: image) else {
          throw DocumentImportError.unreadableImage
        }
        let page = try await source.preparePage()
        fragments.append(
          contentsOf: try await textRecognizer.recognize(
            page: page,
            pageIndex: pageIndex
          )
        )
      }
      return OCRDocumentAssembler.assemble(
        fragments,
        sourcePageCount: scan.pageCount
      )
    }
  }

  func reportScannerFailure() {
    prepareForImportAttempt()
    var nextState = DocumentImportState()
    let requestID = nextState.begin()
    _ = nextState.fail(
      userMessage: DocumentImportError.scannerFailed.userMessage,
      for: requestID
    )
    importState = nextState
    postAccessibilityAnnouncement(CareBriefAccessibilityCopy.scannerFailed(for: appLanguage))
  }

  func cancelImport() {
    let wasImporting = isImporting
    importTask?.cancel()
    importTask = nil
    var nextState = importState
    nextState.cancel()
    importState = nextState
    if wasImporting {
      postAccessibilityAnnouncement(
        CareBriefAccessibilityCopy.recognitionCancelled(for: appLanguage)
      )
    }
  }

  func importDocument(
    operation: @MainActor @escaping () async throws -> OCRDocument
  ) {
    prepareForImportAttempt()
    var nextState = DocumentImportState()
    let requestID = nextState.begin()
    importState = nextState
    postAccessibilityAnnouncement(CareBriefAccessibilityCopy.recognizingText(for: appLanguage))

    importTask = Task { [weak self] in
      guard let self else { return }
      do {
        let document = try await operation()
        try Task.checkCancellation()
        guard document.text.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) != nil else {
          throw DocumentImportError.noRecognizedText
        }
        acceptImport(document, for: requestID)
      } catch is CancellationError {
        return
      } catch let error as DocumentImportError {
        failImport(message: error.userMessage, for: requestID)
      } catch {
        failImport(
          message: DocumentImportError.recognitionFailed.userMessage,
          for: requestID
        )
      }
    }
  }

  private func acceptImport(_ document: OCRDocument, for requestID: UUID) {
    var nextState = importState
    guard nextState.complete(document, for: requestID) else { return }

    importState = nextState
    inputText = document.text
    reviewState = DocumentReviewState(inputText: document.text, language: .unknown)
    resetExportState()
    acceptedImportRevision &+= 1
    importTask = nil
    let announcement = [importSummaryMessage, importCoverageWarningMessage]
      .compactMap { $0 }
      .joined(separator: " ")
    postAccessibilityAnnouncement(announcement)
  }

  private func failImport(message: String, for requestID: UUID) {
    var nextState = importState
    guard nextState.fail(userMessage: message, for: requestID) else { return }
    importState = nextState
    importTask = nil
    postAccessibilityAnnouncement(CareBriefAccessibilityCopy.recognitionFailed(for: appLanguage))
  }

  private func abandonImportAndProvenance() {
    let wasImporting = isImporting
    importTask?.cancel()
    importTask = nil
    var nextState = importState
    nextState.reset()
    importState = nextState
    if wasImporting {
      postAccessibilityAnnouncement(
        CareBriefAccessibilityCopy.recognitionCancelled(for: appLanguage)
      )
    }
  }

  private func prepareForImportAttempt() {
    importTask?.cancel()
    importTask = nil
    resetExportState()
    reviewState = DocumentReviewState(
      inputText: inputText,
      language: reviewState.language
    )
  }

  private func postAccessibilityAnnouncement(_ message: String) {
    guard !message.isEmpty else { return }
    accessibilityAnnouncer.announce(message)
  }

  private func replaceInput(_ text: String, language: DocumentLanguage) {
    guard text != inputText || language != reviewState.language else { return }
    inputText = text
    var nextState = reviewState
    nextState.setInputText(text, language: language)
    reviewState = nextState
  }

  private func resetExportState() {
    resetPreparedExportState()
    outstandingExportReceipts.removeAll()
    latestExportReceipt = nil
    undoResult = nil
  }

  private func validatedUndoResult(
    _ candidate: ActionUndoBatchResult,
    for receipt: ExportReceipt
  ) -> ActionUndoBatchResult {
    let invalidResult = ActionUndoBatchResult(
      operationID: receipt.operationID,
      results: receipt.items.map {
        ActionUndoItemResult(
          actionID: $0.actionID,
          outcome: .failed(.invalidExporterResult)
        )
      }
    )
    guard candidate.operationID == receipt.operationID,
      candidate.results.count == receipt.items.count
    else {
      return invalidResult
    }

    let expectedActionIDs = receipt.items.map(\.actionID)
    guard Set(expectedActionIDs).count == expectedActionIDs.count else {
      return invalidResult
    }
    let outcomesByActionID = Dictionary(grouping: candidate.results, by: \.actionID)
    guard Set(outcomesByActionID.keys) == Set(expectedActionIDs) else {
      return invalidResult
    }

    var orderedResults: [ActionUndoItemResult] = []
    for actionID in expectedActionIDs {
      guard let outcomes = outcomesByActionID[actionID], outcomes.count == 1 else {
        return invalidResult
      }
      orderedResults.append(outcomes[0])
    }
    return ActionUndoBatchResult(
      operationID: receipt.operationID,
      results: orderedResults
    )
  }

  private func resetPreparedExportState() {
    exportPreview = nil
    exportResult = nil
    exportValidationIssuesByActionID = [:]
    exportDestinationOverrides = [:]
    includeResponsiblePartyInNotes = false
  }

  private func exportCompletionAnnouncement(for result: ActionExportBatchResult) -> String {
    var created = 0
    var duplicates = 0
    var failed = 0
    for item in result.results {
      switch item.outcome {
      case .created: created += 1
      case .alreadyAdded: duplicates += 1
      case .failed: failed += 1
      case .skipped: break
      }
    }
    return CareBriefAccessibilityCopy.exportFinished(
      created: created,
      alreadyAdded: duplicates,
      failed: failed,
      for: appLanguage
    )
  }

  private func undoCompletionAnnouncement(for result: ActionUndoBatchResult) -> String {
    let removed = result.results.filter {
      if case .removed = $0.outcome { return true }
      return false
    }.count
    let alreadyRemoved = result.results.filter {
      if case .alreadyRemoved = $0.outcome { return true }
      return false
    }.count
    let failed = result.results.filter {
      if case .failed = $0.outcome { return true }
      return false
    }.count
    return CareBriefAccessibilityCopy.undoFinished(
      removed: removed,
      alreadyRemoved: alreadyRemoved,
      failed: failed,
      for: appLanguage
    )
  }
}

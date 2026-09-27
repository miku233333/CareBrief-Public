import Foundation
import Testing

@testable import CareBriefAppSupport

@Suite struct DocumentImportStateTests {
  @Test func currentImportPublishesRecognizedDocument() throws {
    let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000061")!
    let document = try makeOCRDocument("覆診日期")
    var state = DocumentImportState()

    let startedRequestID = state.begin(requestID: requestID)

    #expect(startedRequestID == requestID)
    #expect(state.status == .processing)
    #expect(state.latestDocument == nil)
    let accepted = state.complete(document, for: requestID)
    #expect(accepted)
    #expect(state.status == .idle)
    #expect(state.latestDocument == document)
  }

  @Test func supersededImportCannotPublish() throws {
    let firstRequestID = UUID(uuidString: "00000000-0000-0000-0000-000000000062")!
    let secondRequestID = UUID(uuidString: "00000000-0000-0000-0000-000000000063")!
    let firstDocument = try makeOCRDocument("舊文件")
    let secondDocument = try makeOCRDocument("新文件")
    var state = DocumentImportState()

    state.begin(requestID: firstRequestID)
    state.begin(requestID: secondRequestID)

    let acceptedFirst = state.complete(firstDocument, for: firstRequestID)
    #expect(!acceptedFirst)
    #expect(state.status == .processing)
    #expect(state.latestDocument == nil)

    let acceptedSecond = state.complete(secondDocument, for: secondRequestID)
    #expect(acceptedSecond)
    #expect(state.status == .idle)
    #expect(state.latestDocument == secondDocument)
  }

  @Test func cancelledImportRejectsLateCompletionAndPreservesLastDocument() throws {
    let savedRequestID = UUID(uuidString: "00000000-0000-0000-0000-000000000064")!
    let cancelledRequestID = UUID(uuidString: "00000000-0000-0000-0000-000000000065")!
    let savedDocument = try makeOCRDocument("已保存文字")
    let lateDocument = try makeOCRDocument("不應出現")
    var state = DocumentImportState()

    state.begin(requestID: savedRequestID)
    _ = state.complete(savedDocument, for: savedRequestID)
    state.begin(requestID: cancelledRequestID)
    state.cancel()
    let acceptedLateResult = state.complete(lateDocument, for: cancelledRequestID)

    #expect(!acceptedLateResult)
    #expect(state.status == .idle)
    #expect(state.latestDocument == savedDocument)
  }

  @Test func failureEndsOnlyTheMatchingImport() throws {
    let failedRequestID = UUID(uuidString: "00000000-0000-0000-0000-000000000066")!
    let nextRequestID = UUID(uuidString: "00000000-0000-0000-0000-000000000067")!
    let lateDocument = try makeOCRDocument("不應接受")
    var state = DocumentImportState()

    state.begin(requestID: failedRequestID)
    let acceptedFailure = state.fail(
      userMessage: "CareBrief could not recognize text in that image.",
      for: failedRequestID
    )
    let acceptedLateResult = state.complete(lateDocument, for: failedRequestID)

    #expect(acceptedFailure)
    #expect(!acceptedLateResult)
    #expect(state.status == .failed(message: "CareBrief could not recognize text in that image."))

    state.begin(requestID: nextRequestID)
    let acceptedStaleFailure = state.fail(userMessage: "Stale error", for: failedRequestID)
    #expect(!acceptedStaleFailure)
    #expect(state.status == .processing)
  }

  @Test func resetClearsImportStateAndProvenance() throws {
    let completedRequestID = UUID(uuidString: "00000000-0000-0000-0000-000000000068")!
    let failedRequestID = UUID(uuidString: "00000000-0000-0000-0000-000000000069")!
    let document = try makeOCRDocument("稍後清除")
    var state = DocumentImportState()

    state.begin(requestID: completedRequestID)
    _ = state.complete(document, for: completedRequestID)
    state.begin(requestID: failedRequestID)
    _ = state.fail(userMessage: "Import failed.", for: failedRequestID)
    state.reset()

    #expect(state.status == .idle)
    #expect(state.latestDocument == nil)
    let acceptedAfterReset = state.complete(document, for: failedRequestID)
    #expect(!acceptedAfterReset)
  }
}

private func makeOCRDocument(_ text: String) throws -> OCRDocument {
  let boundingBox = try #require(
    OCRNormalizedRect(x: 0.1, y: 0.7, width: 0.6, height: 0.1)
  )
  let fragment = try #require(
    OCRTextFragment(pageIndex: 0, text: text, boundingBox: boundingBox)
  )
  return OCRDocumentAssembler.assemble([fragment])
}

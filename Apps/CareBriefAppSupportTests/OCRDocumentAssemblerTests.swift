import CareBriefCore
import Foundation
import Testing

@testable import CareBriefAppSupport

@Suite struct OCRDocumentAssemblerTests {
  @Test func assembledFragmentsPreserveUTF16Traceability() throws {
    let firstBox = try #require(
      OCRNormalizedRect(x: 0.1, y: 0.8, width: 0.4, height: 0.1)
    )
    let secondBox = try #require(
      OCRNormalizedRect(x: 0.1, y: 0.6, width: 0.6, height: 0.1)
    )

    let document = OCRDocumentAssembler.assemble([
      try #require(OCRTextFragment(pageIndex: 0, text: "A👵🏻覆診", boundingBox: firstBox)),
      try #require(OCRTextFragment(pageIndex: 0, text: "請攜帶身份證", boundingBox: secondBox)),
    ])

    #expect(document.text == "A👵🏻覆診\n請攜帶身份證")
    #expect(document.fragments.count == 2)
    #expect(document.fragments[0].pageIndex == 0)
    #expect(document.fragments[0].boundingBox == firstBox)
    #expect(document.fragments[0].range.substring(in: document.text) == "A👵🏻覆診")
    #expect(document.fragments[1].range.substring(in: document.text) == "請攜帶身份證")
    #expect(document.fragments[1].range.location == ("A👵🏻覆診\n" as NSString).length)
  }

  @Test func fragmentsAreAssembledByPageThenVisualReadingOrder() throws {
    let upperLeft = try #require(
      OCRNormalizedRect(x: 0.1, y: 0.8, width: 0.3, height: 0.1)
    )
    let upperRight = try #require(
      OCRNormalizedRect(x: 0.6, y: 0.8, width: 0.3, height: 0.1)
    )
    let lower = try #require(
      OCRNormalizedRect(x: 0.1, y: 0.4, width: 0.5, height: 0.1)
    )

    let document = OCRDocumentAssembler.assemble([
      try #require(OCRTextFragment(pageIndex: 1, text: "第二頁", boundingBox: upperLeft)),
      try #require(OCRTextFragment(pageIndex: 0, text: "右上", boundingBox: upperRight)),
      try #require(OCRTextFragment(pageIndex: 0, text: "下方", boundingBox: lower)),
      try #require(OCRTextFragment(pageIndex: 0, text: "左上", boundingBox: upperLeft)),
    ])

    #expect(document.text == "左上\n右上\n下方\n\n第二頁")
    #expect(document.fragments.map(\.pageIndex) == [0, 0, 0, 1])
  }

  @Test func invalidNormalizedProvenanceIsRejected() throws {
    #expect(OCRNormalizedRect(x: .nan, y: 0, width: 0.5, height: 0.5) == nil)
    #expect(OCRNormalizedRect(x: -0.1, y: 0, width: 0.5, height: 0.5) == nil)
    #expect(OCRNormalizedRect(x: 0, y: 0, width: 0, height: 0.5) == nil)
    #expect(OCRNormalizedRect(x: 0.8, y: 0, width: 0.3, height: 0.5) == nil)

    let fullImage = try #require(
      OCRNormalizedRect(x: 0, y: 0, width: 1, height: 1)
    )
    #expect(OCRTextFragment(pageIndex: -1, text: "覆診", boundingBox: fullImage) == nil)
    #expect(OCRTextFragment(pageIndex: 0, text: " \n ", boundingBox: fullImage) == nil)
  }

  @Test func sourcePageCoverageReportsPagesWithoutRecognizedText() throws {
    let boundingBox = try #require(
      OCRNormalizedRect(x: 0.1, y: 0.7, width: 0.6, height: 0.1)
    )
    let firstPageFragment = try #require(
      OCRTextFragment(pageIndex: 0, text: "第一頁", boundingBox: boundingBox)
    )

    let document = OCRDocumentAssembler.assemble(
      [firstPageFragment],
      sourcePageCount: 2
    )

    #expect(document.sourcePageCount == 2)
    #expect(document.pagesWithoutText == [1])
    #expect(document.hasIncompletePages)
    #expect(document.text == "第一頁")
  }
}

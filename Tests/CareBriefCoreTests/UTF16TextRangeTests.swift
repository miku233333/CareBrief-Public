import Foundation
import Testing

@testable import CareBriefCore

@Suite struct UTF16TextRangeTests {
  @Test func rangeRoundTripsChineseAfterEmoji() throws {
    let text = "A👵🏻覆診Z"
    let range = try #require(UTF16TextRange.range(of: "覆診", in: text))

    #expect(range.substring(in: text) == "覆診")
    #expect(range.location == ("A👵🏻" as NSString).length)
    #expect(range.length == ("覆診" as NSString).length)
  }

  @Test func negativeRangeIsRejected() {
    #expect(UTF16TextRange(location: -1, length: 1) == nil)
    #expect(UTF16TextRange(location: 0, length: -1) == nil)
    #expect(UTF16TextRange(location: Int.max, length: 1) == nil)
  }

  @Test func outOfBoundsRangeDoesNotResolve() throws {
    let range = try #require(UTF16TextRange(location: 2, length: 99))
    #expect(range.substring(in: "短文") == nil)
  }

  @Test func outOfBoundsSearchRangeReturnsNilInsteadOfCallingFoundation() throws {
    let searchRange = try #require(UTF16TextRange(location: 5, length: 0))
    #expect(UTF16TextRange.range(of: "a", in: "abc", searchRange: searchRange) == nil)
  }

  @Test func invalidDecodedRangeIsRejected() {
    let data = Data(#"{"location":-1,"length":1}"#.utf8)
    var didThrow = false
    do {
      _ = try JSONDecoder().decode(UTF16TextRange.self, from: data)
    } catch {
      didThrow = true
    }
    #expect(didThrow)
  }

  @Test func evidenceValidatesAgainstDocumentIdentityAndText() throws {
    let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let document = SourceDocument(id: id, text: "請攜帶身份證")
    let range = try #require(UTF16TextRange.range(of: "身份證", in: document.text))
    let evidence = SourceEvidence(
      documentID: id,
      range: range,
      text: "身份證",
      ruleID: "test"
    )

    #expect(evidence.resolves(in: document))
    #expect(!evidence.resolves(in: SourceDocument(text: document.text)))
  }
}

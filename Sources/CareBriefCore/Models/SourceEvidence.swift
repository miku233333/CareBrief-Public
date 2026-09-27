import Foundation

public struct SourceEvidence: Codable, Equatable, Hashable, Sendable {
  public let documentID: UUID
  public let range: UTF16TextRange
  public let text: String
  public let ruleID: String

  public init(
    documentID: UUID,
    range: UTF16TextRange,
    text: String,
    ruleID: String
  ) {
    self.documentID = documentID
    self.range = range
    self.text = text
    self.ruleID = ruleID
  }

  /// Confirms that this evidence still points to the same source text.
  public func resolves(in document: SourceDocument) -> Bool {
    document.id == documentID && range.substring(in: document.text) == text
  }
}

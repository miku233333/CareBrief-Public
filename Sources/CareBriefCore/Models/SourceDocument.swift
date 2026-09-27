import Foundation

public enum DocumentLanguage: String, Codable, CaseIterable, Sendable {
  case traditionalChinese = "zh-Hant"
  case english = "en"
  case mixed
  case unknown
}

public struct SourceDocument: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let text: String
  public let language: DocumentLanguage

  public init(
    id: UUID = UUID(),
    text: String,
    language: DocumentLanguage = .unknown
  ) {
    self.id = id
    self.text = text
    self.language = language
  }
}

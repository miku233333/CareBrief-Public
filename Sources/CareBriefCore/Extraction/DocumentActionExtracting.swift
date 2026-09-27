public protocol DocumentActionExtracting: Sendable {
  func extract(from document: SourceDocument) -> ExtractionResult
}

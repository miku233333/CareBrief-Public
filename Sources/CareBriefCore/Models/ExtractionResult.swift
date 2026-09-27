import Foundation

public struct ExtractionResult: Codable, Equatable, Sendable {
  private enum CodingKeys: String, CodingKey {
    case documentID
    case actions
    case warnings
    case requiresReview
  }

  public let documentID: UUID
  public let actions: [ActionCard]
  public let warnings: [String]

  public var requiresReview: Bool {
    !warnings.isEmpty || actions.contains(where: \.needsReview)
  }

  public init(
    documentID: UUID,
    actions: [ActionCard],
    warnings: [String] = []
  ) {
    self.documentID = documentID
    self.actions = actions
    let mismatchedEvidenceWarning =
      "One or more actions reference a different source document and require review."
    if actions.contains(where: { $0.evidence.documentID != documentID }) {
      self.warnings =
        warnings.contains(mismatchedEvidenceWarning)
        ? warnings : warnings + [mismatchedEvidenceWarning]
    } else {
      self.warnings = warnings
    }
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      documentID: try container.decode(UUID.self, forKey: .documentID),
      actions: try container.decode([ActionCard].self, forKey: .actions),
      warnings: try container.decode([String].self, forKey: .warnings)
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(documentID, forKey: .documentID)
    try container.encode(actions, forKey: .actions)
    try container.encode(warnings, forKey: .warnings)
    try container.encode(requiresReview, forKey: .requiresReview)
  }
}

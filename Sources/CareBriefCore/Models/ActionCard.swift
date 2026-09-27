import Foundation

public enum ActionCategory: String, Codable, CaseIterable, Sendable {
  case appointment
  case deadline
  case preparation
  case requiredItem
  case contact
  case nextStep
  case location
}

public enum ConfidenceLevel: String, Codable, CaseIterable, Sendable {
  case high
  case medium
  case low
}

public struct ActionDateTime: Codable, Equatable, Hashable, Sendable {
  private enum CodingKeys: String, CodingKey {
    case year
    case month
    case day
    case hour
    case minute
    case isAmbiguous
    case iso8601Local
  }

  public let year: Int
  public let month: Int
  public let day: Int
  public let hour: Int?
  public let minute: Int?
  public let isAmbiguous: Bool

  public var hasTime: Bool { hour != nil }

  public var iso8601Local: String {
    guard let hour else {
      return String(format: "%04d-%02d-%02d", year, month, day)
    }

    return String(
      format: "%04d-%02d-%02dT%02d:%02d",
      year,
      month,
      day,
      hour,
      minute ?? 0
    )
  }

  public init?(
    year: Int,
    month: Int,
    day: Int,
    hour: Int? = nil,
    minute: Int? = nil,
    isAmbiguous: Bool = false
  ) {
    guard (1...12).contains(month),
      (0...23).contains(hour ?? 0),
      (0...59).contains(minute ?? 0)
    else {
      return nil
    }

    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(secondsFromGMT: 0)
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour ?? 12
    components.minute = minute ?? 0

    guard let date = components.date else { return nil }
    let verified = components.calendar?.dateComponents(
      [.year, .month, .day],
      from: date
    )
    guard verified?.year == year,
      verified?.month == month,
      verified?.day == day
    else {
      return nil
    }

    self.year = year
    self.month = month
    self.day = day
    self.hour = hour
    self.minute = hour == nil ? nil : (minute ?? 0)
    self.isAmbiguous = isAmbiguous
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let year = try container.decode(Int.self, forKey: .year)
    let month = try container.decode(Int.self, forKey: .month)
    let day = try container.decode(Int.self, forKey: .day)
    let hour = try container.decodeIfPresent(Int.self, forKey: .hour)
    let minute = try container.decodeIfPresent(Int.self, forKey: .minute)
    let isAmbiguous = try container.decode(Bool.self, forKey: .isAmbiguous)
    guard
      let value = ActionDateTime(
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute,
        isAmbiguous: isAmbiguous
      )
    else {
      throw DecodingError.dataCorruptedError(
        forKey: .day,
        in: container,
        debugDescription: "ActionDateTime contains invalid calendar components."
      )
    }
    self = value
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(year, forKey: .year)
    try container.encode(month, forKey: .month)
    try container.encode(day, forKey: .day)
    try container.encodeIfPresent(hour, forKey: .hour)
    try container.encodeIfPresent(minute, forKey: .minute)
    try container.encode(isAmbiguous, forKey: .isAmbiguous)
    try container.encode(iso8601Local, forKey: .iso8601Local)
  }
}

public struct ActionCard: Codable, Equatable, Identifiable, Sendable {
  private enum CodingKeys: String, CodingKey {
    case id
    case category
    case title
    case detail
    case dateTime
    case location
    case items
    case contact
    case evidence
    case confidence
    case needsReview
  }

  public let id: String
  public let category: ActionCategory
  public let title: String
  public let detail: String
  public let dateTime: ActionDateTime?
  public let location: String?
  public let items: [String]
  public let contact: String?
  public let evidence: SourceEvidence
  public let confidence: ConfidenceLevel
  public let needsReview: Bool

  public init(
    id: String? = nil,
    category: ActionCategory,
    title: String,
    detail: String,
    dateTime: ActionDateTime? = nil,
    location: String? = nil,
    items: [String] = [],
    contact: String? = nil,
    evidence: SourceEvidence,
    confidence: ConfidenceLevel,
    needsReview: Bool
  ) {
    self.id =
      id
      ?? [
        evidence.documentID.uuidString,
        evidence.ruleID,
        String(evidence.range.location),
        String(evidence.range.length),
      ].joined(separator: ":")
    self.category = category
    self.title = title
    self.detail = detail
    self.dateTime = dateTime
    self.location = location
    self.items = items
    self.contact = contact
    self.evidence = evidence
    self.confidence = confidence
    self.needsReview = needsReview || dateTime?.isAmbiguous == true
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decode(String.self, forKey: .id),
      category: try container.decode(ActionCategory.self, forKey: .category),
      title: try container.decode(String.self, forKey: .title),
      detail: try container.decode(String.self, forKey: .detail),
      dateTime: try container.decodeIfPresent(ActionDateTime.self, forKey: .dateTime),
      location: try container.decodeIfPresent(String.self, forKey: .location),
      items: try container.decode([String].self, forKey: .items),
      contact: try container.decodeIfPresent(String.self, forKey: .contact),
      evidence: try container.decode(SourceEvidence.self, forKey: .evidence),
      confidence: try container.decode(ConfidenceLevel.self, forKey: .confidence),
      needsReview: try container.decode(Bool.self, forKey: .needsReview)
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(category, forKey: .category)
    try container.encode(title, forKey: .title)
    try container.encode(detail, forKey: .detail)
    try container.encodeIfPresent(dateTime, forKey: .dateTime)
    try container.encodeIfPresent(location, forKey: .location)
    try container.encode(items, forKey: .items)
    try container.encodeIfPresent(contact, forKey: .contact)
    try container.encode(evidence, forKey: .evidence)
    try container.encode(confidence, forKey: .confidence)
    try container.encode(needsReview, forKey: .needsReview)
  }
}

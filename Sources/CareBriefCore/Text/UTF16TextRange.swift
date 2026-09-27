import Foundation

/// A source range expressed in UTF-16 code units, matching `NSRange`, Vision,
/// and TextKit conventions on Apple platforms.
public struct UTF16TextRange: Codable, Equatable, Hashable, Sendable {
  private enum CodingKeys: String, CodingKey {
    case location
    case length
  }

  public let location: Int
  public let length: Int

  public var endLocation: Int { location + length }

  public var nsRange: NSRange {
    NSRange(location: location, length: length)
  }

  public init?(location: Int, length: Int) {
    guard location >= 0,
      length >= 0,
      length <= Int.max - location
    else {
      return nil
    }
    self.location = location
    self.length = length
  }

  public init?(_ range: NSRange) {
    guard range.location != NSNotFound else { return nil }
    self.init(location: range.location, length: range.length)
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let location = try container.decode(Int.self, forKey: .location)
    let length = try container.decode(Int.self, forKey: .length)
    guard let value = UTF16TextRange(location: location, length: length) else {
      throw DecodingError.dataCorruptedError(
        forKey: .length,
        in: container,
        debugDescription: "UTF16TextRange must be non-negative and must not overflow."
      )
    }
    self = value
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(location, forKey: .location)
    try container.encode(length, forKey: .length)
  }

  public func substring(in text: String) -> String? {
    guard endLocation <= text.utf16.count,
      let range = Range(nsRange, in: text)
    else {
      return nil
    }

    return String(text[range])
  }

  public func contains(_ other: UTF16TextRange) -> Bool {
    other.location >= location && other.endLocation <= endLocation
  }

  public static func range(
    of needle: String,
    in text: String,
    options: NSString.CompareOptions = [],
    searchRange: UTF16TextRange? = nil
  ) -> UTF16TextRange? {
    let source = text as NSString
    let targetRange: NSRange
    if let searchRange {
      guard searchRange.location <= source.length,
        searchRange.length <= source.length - searchRange.location
      else {
        return nil
      }
      targetRange = searchRange.nsRange
    } else {
      targetRange = NSRange(location: 0, length: source.length)
    }
    let result = source.range(of: needle, options: options, range: targetRange)
    return UTF16TextRange(result)
  }
}

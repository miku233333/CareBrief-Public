import Foundation

public struct ParsedDocumentDateTime: Equatable, Sendable {
  public let value: ActionDateTime
  public let rawText: String
  public let range: UTF16TextRange
  public let confidence: ConfidenceLevel

  public init(
    value: ActionDateTime,
    rawText: String,
    range: UTF16TextRange,
    confidence: ConfidenceLevel
  ) {
    self.value = value
    self.rawText = rawText
    self.range = range
    self.confidence = confidence
  }
}

public struct DocumentDateTimeParser: Sendable {
  private static let englishMonths: [String: Int] = [
    "jan": 1, "january": 1,
    "feb": 2, "february": 2,
    "mar": 3, "march": 3,
    "apr": 4, "april": 4,
    "may": 5,
    "jun": 6, "june": 6,
    "jul": 7, "july": 7,
    "aug": 8, "august": 8,
    "sep": 9, "sept": 9, "september": 9,
    "oct": 10, "october": 10,
    "nov": 11, "november": 11,
    "dec": 12, "december": 12,
  ]

  public init() {}

  public func firstMatch(in text: String) -> ParsedDocumentDateTime? {
    matches(in: text).first
  }

  public func matches(in text: String) -> [ParsedDocumentDateTime] {
    let candidates =
      chineseMatches(in: text)
      + isoMatches(in: text)
      + englishDayFirstMatches(in: text)
      + englishMonthFirstMatches(in: text)

    var seenRanges = Set<UTF16TextRange>()
    return
      candidates
      .sorted {
        if $0.range.location == $1.range.location {
          return $0.range.length > $1.range.length
        }
        return $0.range.location < $1.range.location
      }
      .filter { seenRanges.insert($0.range).inserted }
  }

  private func chineseMatches(in text: String) -> [ParsedDocumentDateTime] {
    matches(
      pattern:
        #"(?<![0-9])([12][0-9]{3})\s*年\s*([0-9]{1,2})\s*月\s*([0-9]{1,2})\s*日(?:\s*(上午|早上|下午|晚上)?\s*([0-9]{1,2})\s*(?:時|點)(?:\s*([0-9]{1,2})\s*分)?)?(?!\s*(?:上午|早上|下午|晚上|[0-9]|半|分|時|點))"#,
      in: text
    ) { match, source in
      guard let year = integer(at: 1, match: match, source: source),
        let month = integer(at: 2, match: match, source: source),
        let day = integer(at: 3, match: match, source: source)
      else {
        return nil
      }

      let modifier = string(at: 4, match: match, source: source)
      let parsedHour = integer(at: 5, match: match, source: source)
      let minute = integer(at: 6, match: match, source: source)
      let crossesUnclearMidnightBoundary = modifier == "晚上" && parsedHour == 12
      let hasAmbiguousHour =
        crossesUnclearMidnightBoundary
        || (modifier == nil && parsedHour.map { (1...12).contains($0) } == true)
      let hour = hasAmbiguousHour ? nil : adjustedHour(parsedHour, modifier: modifier)
      if parsedHour != nil, !hasAmbiguousHour, hour == nil { return nil }

      return ActionDateTime(
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: hasAmbiguousHour ? nil : minute,
        isAmbiguous: hasAmbiguousHour
      )
    }
  }

  private func isoMatches(in text: String) -> [ParsedDocumentDateTime] {
    matches(
      pattern:
        #"(?<![0-9])([12][0-9]{3})[-/]([0-9]{1,2})[-/]([0-9]{1,2})(?:[ T]([0-9]{1,2}):([0-9]{2}))?(?![0-9]|[ T][0-9])"#,
      in: text
    ) { match, source in
      guard let year = integer(at: 1, match: match, source: source),
        let month = integer(at: 2, match: match, source: source),
        let day = integer(at: 3, match: match, source: source)
      else {
        return nil
      }

      return ActionDateTime(
        year: year,
        month: month,
        day: day,
        hour: integer(at: 4, match: match, source: source),
        minute: integer(at: 5, match: match, source: source)
      )
    }
  }

  private func englishDayFirstMatches(in text: String) -> [ParsedDocumentDateTime] {
    matches(
      pattern:
        #"\b([0-9]{1,2})\s+(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+([12][0-9]{3})(?:\s+(?:at\s+)?([0-9]{1,2})(?::([0-9]{2}))?\s*(am|pm)?)?\b(?!:[0-9]|\s+(?:at\s+)?[0-9])"#,
      in: text,
      options: [.caseInsensitive]
    ) { match, source in
      englishDate(
        match: match,
        source: source,
        dayGroup: 1,
        monthGroup: 2,
        yearGroup: 3,
        hourGroup: 4,
        minuteGroup: 5,
        meridiemGroup: 6
      )
    }
  }

  private func englishMonthFirstMatches(in text: String) -> [ParsedDocumentDateTime] {
    matches(
      pattern:
        #"\b(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+([0-9]{1,2}),?\s+([12][0-9]{3})(?:\s+(?:at\s+)?([0-9]{1,2})(?::([0-9]{2}))?\s*(am|pm)?)?\b(?!:[0-9]|\s+(?:at\s+)?[0-9])"#,
      in: text,
      options: [.caseInsensitive]
    ) { match, source in
      englishDate(
        match: match,
        source: source,
        dayGroup: 2,
        monthGroup: 1,
        yearGroup: 3,
        hourGroup: 4,
        minuteGroup: 5,
        meridiemGroup: 6
      )
    }
  }

  private func matches(
    pattern: String,
    in text: String,
    options: NSRegularExpression.Options = [],
    makeValue: (NSTextCheckingResult, NSString) -> ActionDateTime?
  ) -> [ParsedDocumentDateTime] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
      return []
    }

    let source = text as NSString
    let fullRange = NSRange(location: 0, length: source.length)
    return regex.matches(in: text, range: fullRange).compactMap { match in
      guard let value = makeValue(match, source),
        let range = UTF16TextRange(match.range)
      else {
        return nil
      }

      return ParsedDocumentDateTime(
        value: value,
        rawText: source.substring(with: match.range),
        range: range,
        confidence: value.hasTime ? .high : .medium
      )
    }
  }

  private func englishDate(
    match: NSTextCheckingResult,
    source: NSString,
    dayGroup: Int,
    monthGroup: Int,
    yearGroup: Int,
    hourGroup: Int,
    minuteGroup: Int,
    meridiemGroup: Int
  ) -> ActionDateTime? {
    guard let year = integer(at: yearGroup, match: match, source: source),
      let day = integer(at: dayGroup, match: match, source: source),
      let monthText = string(at: monthGroup, match: match, source: source),
      let month = Self.englishMonths[monthText.lowercased()]
    else {
      return nil
    }

    let rawHour = integer(at: hourGroup, match: match, source: source)
    let minute = integer(at: minuteGroup, match: match, source: source)
    let meridiem = string(at: meridiemGroup, match: match, source: source)
    let hasAmbiguousHour =
      meridiem == nil
      && rawHour.map { (1...12).contains($0) } == true
    let hour = hasAmbiguousHour ? nil : adjustedHour(rawHour, modifier: meridiem)
    if rawHour != nil, !hasAmbiguousHour, hour == nil { return nil }
    return ActionDateTime(
      year: year,
      month: month,
      day: day,
      hour: hour,
      minute: hasAmbiguousHour ? nil : minute,
      isAmbiguous: hasAmbiguousHour
    )
  }

  private func adjustedHour(_ hour: Int?, modifier: String?) -> Int? {
    guard var hour else { return nil }
    let normalized = modifier?.lowercased()

    if normalized != nil, !(1...12).contains(hour) {
      return nil
    }

    if ["下午", "晚上", "pm"].contains(normalized), hour < 12 {
      hour += 12
    } else if ["上午", "早上", "am"].contains(normalized), hour == 12 {
      hour = 0
    }

    return hour
  }

  private func integer(
    at index: Int,
    match: NSTextCheckingResult,
    source: NSString
  ) -> Int? {
    string(at: index, match: match, source: source).flatMap(Int.init)
  }

  private func string(
    at index: Int,
    match: NSTextCheckingResult,
    source: NSString
  ) -> String? {
    guard index < match.numberOfRanges else { return nil }
    let range = match.range(at: index)
    guard range.location != NSNotFound else { return nil }
    return source.substring(with: range)
  }
}

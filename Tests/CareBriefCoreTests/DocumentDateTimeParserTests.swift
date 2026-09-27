import Testing

@testable import CareBriefCore

@Suite struct DocumentDateTimeParserTests {
  private let parser = DocumentDateTimeParser()

  @Test func parsesChineseDateAndAfternoonTime() throws {
    let match = try #require(parser.firstMatch(in: "請於2026年8月15日下午3時30分覆診"))

    #expect(match.value.iso8601Local == "2026-08-15T15:30")
    #expect(match.rawText == "2026年8月15日下午3時30分")
    #expect(match.confidence == .high)
  }

  @Test func parsesISODateAndTime() throws {
    let match = try #require(parser.firstMatch(in: "Appointment: 2026-08-15 09:05"))
    #expect(match.value.iso8601Local == "2026-08-15T09:05")
  }

  @Test func parsesEnglishMonthFirstDate() throws {
    let match = try #require(
      parser.firstMatch(in: "Attend on August 15, 2026 at 9:00 AM")
    )
    #expect(match.value.iso8601Local == "2026-08-15T09:00")
  }

  @Test func parsesEnglishDayFirstDateWithoutTime() throws {
    let match = try #require(parser.firstMatch(in: "Submit by 17 July 2026"))
    #expect(match.value.iso8601Local == "2026-07-17")
    #expect(!match.value.hasTime)
    #expect(match.confidence == .medium)
  }

  @Test func rejectsInvalidCalendarDate() {
    #expect(parser.firstMatch(in: "2026-02-30 09:00") == nil)
  }

  @Test func rejectsInvalidTwelveHourClockValue() {
    #expect(parser.firstMatch(in: "August 15, 2026 at 15:00 PM") == nil)
  }

  @Test func unqualifiedTwelveHourValuesRemainAmbiguous() throws {
    for text in [
      "Appointment August 15, 2026 at 3:00",
      "請於2026年8月15日3時覆診",
    ] {
      let match = try #require(parser.firstMatch(in: text))
      #expect(!match.value.hasTime)
      #expect(match.value.isAmbiguous)
      #expect(match.confidence == .medium)
    }
  }

  @Test func rejectsMalformedDateAndTimeSuffixes() {
    for text in [
      "請於2026年8月15日上午9點半覆診",
      "請於2026年8月15日上午9時30覆診",
      "Appointment August 15, 2026 at 9:5 AM",
      "Appointment 2026-08-150",
    ] {
      #expect(parser.firstMatch(in: text) == nil)
    }
  }

  @Test func eveningTwelveOClockRemainsAmbiguous() throws {
    let match = try #require(parser.firstMatch(in: "2026年8月15日晚上12時30分"))
    #expect(!match.value.hasTime)
    #expect(match.value.isAmbiguous)
    #expect(match.confidence == .medium)
  }
}

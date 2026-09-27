import CareBriefCore
import Foundation
import Testing

@testable import CareBriefAppSupport

@Suite struct ActionDraftTests {
  @Test func responsiblePartyValidatesCustomNamesAtThePublicBoundary() {
    #expect(ResponsibleParty.me.validationIssue == nil)
    #expect(ResponsibleParty.familyOrCaregiver.validationIssue == nil)
    #expect(ResponsibleParty.custom("  ").validationIssue == .emptyCustomName)
    #expect(ResponsibleParty.custom(String(repeating: "家", count: 80)).validationIssue == nil)
    #expect(
      ResponsibleParty.custom(String(repeating: "家", count: 81)).validationIssue
        == .customNameTooLong(maximum: 80)
    )
  }

  @Test func draftsGroupOnlyExplicitLocalTodayDatesAsToday() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Hong_Kong"))
    let today = try #require(
      calendar.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 12))
    )
    let todayDraft = makeDraft(
      id: "today",
      dateTime: ActionDateTime(year: 2026, month: 7, day: 11)
    )
    let scheduledDraft = makeDraft(
      id: "scheduled",
      dateTime: ActionDateTime(year: 2026, month: 7, day: 12)
    )
    let unscheduledDraft = makeDraft(id: "unscheduled", dateTime: nil)
    let ambiguousTodayDraft = makeDraft(
      id: "ambiguous-today",
      dateTime: ActionDateTime(
        year: 2026,
        month: 7,
        day: 11,
        isAmbiguous: true
      )
    )

    let groups = ActionDraftGrouper.group(
      [unscheduledDraft, ambiguousTodayDraft, scheduledDraft, todayDraft],
      today: today,
      calendar: calendar
    )

    #expect(groups.today.map(\.id) == ["today"])
    #expect(groups.scheduled.map(\.id) == ["scheduled"])
    #expect(groups.unscheduled.map(\.id) == ["unscheduled", "ambiguous-today"])
  }

  @Test func groupingUsesGregorianModelDatesEvenWithANonGregorianSystemCalendar() throws {
    let timeZone = try #require(TimeZone(identifier: "Asia/Hong_Kong"))
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = timeZone
    let today = try #require(
      gregorian.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 12))
    )
    var buddhist = Calendar(identifier: .buddhist)
    buddhist.timeZone = timeZone
    let draft = makeDraft(
      id: "gregorian-today",
      dateTime: ActionDateTime(year: 2026, month: 7, day: 11)
    )

    let groups = ActionDraftGrouper.group(
      [draft],
      today: today,
      calendar: buddhist
    )

    #expect(groups.today.map(\.id) == [draft.id])
  }

  @Test func groupingUsesTheInjectedLocalDayAcrossUTCDateBoundaries() throws {
    let hongKong = try #require(TimeZone(identifier: "Asia/Hong_Kong"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = hongKong
    let utc = try #require(TimeZone(secondsFromGMT: 0))
    var utcCalendar = Calendar(identifier: .gregorian)
    utcCalendar.timeZone = utc
    let instant = try #require(
      utcCalendar.date(
        from: DateComponents(year: 2026, month: 7, day: 11, hour: 16, minute: 30)
      )
    )
    let localToday = makeDraft(
      id: "local-today",
      dateTime: ActionDateTime(year: 2026, month: 7, day: 12)
    )
    let utcDay = makeDraft(
      id: "utc-day",
      dateTime: ActionDateTime(year: 2026, month: 7, day: 11)
    )

    let groups = ActionDraftGrouper.group(
      [localToday, utcDay],
      today: instant,
      calendar: calendar
    )

    #expect(groups.today.map(\.id) == [localToday.id])
    #expect(groups.scheduled.map(\.id) == [utcDay.id])
    #expect(groups.unscheduled.isEmpty)
  }
}

private func makeDraft(id: String, dateTime: ActionDateTime?) -> ActionDraft {
  ActionDraft(
    sourceActionID: id,
    title: id,
    detail: id,
    dateTime: dateTime,
    location: nil,
    items: [],
    contact: nil
  )
}

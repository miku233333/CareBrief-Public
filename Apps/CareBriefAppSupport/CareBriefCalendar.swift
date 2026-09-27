import Foundation

public enum CareBriefCalendar {
  public static func localGregorian(
    timeZone: TimeZone = .autoupdatingCurrent
  ) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
  }
}

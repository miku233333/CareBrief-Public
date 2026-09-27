import CareBriefAppSupport
import CareBriefCore
import Foundation

extension ActionDateTime {
  func localizedCareBriefDisplay(for language: CareBriefAppLanguage) -> String {
    let calendar = CareBriefCalendar.localGregorian()
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour ?? 12
    components.minute = minute ?? 0
    guard let date = calendar.date(from: components) else { return iso8601Local }
    let roundTrip = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute],
      from: date
    )
    guard roundTrip.year == year,
      roundTrip.month == month,
      roundTrip.day == day,
      !hasTime || (roundTrip.hour == hour && roundTrip.minute == (minute ?? 0))
    else {
      return iso8601Local
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: language.rawValue)
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.dateStyle = .medium
    formatter.timeStyle = hasTime ? .short : .none
    return formatter.string(from: date)
  }
}

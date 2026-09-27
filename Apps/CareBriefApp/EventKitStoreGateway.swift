import CareBriefAppSupport
import CareBriefCore
@preconcurrency import EventKit
import Foundation

enum EventKitEntity: Equatable, Hashable, Sendable {
  case events
  case reminders

  var eventKitType: EKEntityType {
    switch self {
    case .events: .event
    case .reminders: .reminder
    }
  }
}

struct EventKitItemSnapshot: Equatable, Sendable {
  let identifier: String?
  let destination: ActionExportDestination
  let markerURLString: String?
}

enum EventKitGatewayRemovalResult: Equatable, Sendable {
  case removed
  case missing
  case markerMismatch
  case typeMismatch
  case failed
}

protocol EventKitStoreGateway: Sendable {
  func authorizationStatusRawValue(for entity: EventKitEntity) async -> Int
  func requestFullAccess(to entity: EventKitEntity) async throws -> Bool

  @available(iOS, introduced: 6.0, deprecated: 17.0)
  func requestLegacyAccess(to entity: EventKitEntity) async throws -> Bool

  func matchingItems(
    destination: ActionExportDestination,
    startDate: Date?,
    endDate: Date?,
    expectedMarkerURLString: String
  ) async throws -> [EventKitItemSnapshot]

  func create(
    request: ActionExportRequest,
    markerURL: URL,
    calendar: Calendar
  ) async throws -> EventKitItemSnapshot

  func removeItem(
    identifier: String,
    destination: ActionExportDestination,
    expectedMarkerURLString: String
  ) async -> EventKitGatewayRemovalResult
}

actor SystemEventKitStoreGateway: EventKitStoreGateway {
  private let eventStore: EKEventStore

  init() {
    self.eventStore = EKEventStore()
  }

  func authorizationStatusRawValue(for entity: EventKitEntity) async -> Int {
    EKEventStore.authorizationStatus(for: entity.eventKitType).rawValue
  }

  func requestFullAccess(to entity: EventKitEntity) async throws -> Bool {
    guard #available(iOS 17.0, *) else { return false }
    switch entity {
    case .events:
      return try await eventStore.requestFullAccessToEvents()
    case .reminders:
      return try await eventStore.requestFullAccessToReminders()
    }
  }

  @available(iOS, introduced: 6.0, deprecated: 17.0)
  func requestLegacyAccess(to entity: EventKitEntity) async throws -> Bool {
    try await eventStore.requestAccess(to: entity.eventKitType)
  }

  func matchingItems(
    destination: ActionExportDestination,
    startDate: Date?,
    endDate: Date?,
    expectedMarkerURLString: String
  ) async throws -> [EventKitItemSnapshot] {
    switch destination {
    case .calendar:
      guard let startDate, let endDate else { return [] }
      let predicate = eventStore.predicateForEvents(
        withStart: startDate,
        end: endDate,
        calendars: nil
      )
      return eventStore.events(matching: predicate).compactMap {
        let item = snapshot(from: $0, destination: .calendar)
        return item.markerURLString == expectedMarkerURLString ? item : nil
      }
    case .reminder:
      let predicate = eventStore.predicateForReminders(in: nil)
      return try await withCheckedThrowingContinuation { continuation in
        eventStore.fetchReminders(matching: predicate) { reminders in
          guard let reminders else {
            continuation.resume(throwing: ActionExportFailure.duplicateLookupFailed)
            return
          }
          let snapshots = reminders.compactMap {
            let item = snapshot(from: $0, destination: .reminder)
            return item.markerURLString == expectedMarkerURLString ? item : nil
          }
          continuation.resume(returning: snapshots)
        }
      }
    case .skip:
      return []
    }
  }

  func create(
    request: ActionExportRequest,
    markerURL: URL,
    calendar: Calendar
  ) async throws -> EventKitItemSnapshot {
    switch request.destination {
    case .calendar:
      guard let defaultCalendar = eventStore.defaultCalendarForNewEvents else {
        throw ActionExportFailure.noDefaultCalendar
      }
      guard
        let startDate = EventKitDateResolver.localDate(
          from: request.dateTime,
          calendar: calendar
        )
      else {
        throw ActionExportFailure.invalidDate
      }
      let event = EKEvent(eventStore: eventStore)
      event.calendar = defaultCalendar
      event.title = request.title
      event.location = normalized(request.location)
      event.notes = normalized(request.notes)
      event.url = markerURL
      event.isAllDay = request.isAllDay
      if request.isAllDay {
        event.startDate = calendar.startOfDay(for: startDate)
        guard let endDate = calendar.date(byAdding: .day, value: 1, to: event.startDate) else {
          throw ActionExportFailure.invalidDate
        }
        event.endDate = endDate
      } else {
        event.startDate = startDate
        guard
          let endDate = calendar.date(
            byAdding: .minute,
            value: request.durationMinutes ?? 60,
            to: startDate
          )
        else {
          throw ActionExportFailure.invalidDate
        }
        event.endDate = endDate
        event.timeZone = calendar.timeZone
      }
      do {
        try eventStore.save(event, span: .thisEvent, commit: true)
      } catch {
        throw ActionExportFailure.saveFailed
      }
      return snapshot(from: event, destination: .calendar)

    case .reminder:
      guard let defaultList = eventStore.defaultCalendarForNewReminders() else {
        throw ActionExportFailure.noDefaultReminderList
      }
      let reminder = EKReminder(eventStore: eventStore)
      reminder.calendar = defaultList
      reminder.title = request.title
      reminder.notes = reminderNotes(for: request)
      reminder.url = markerURL
      if let dateTime = request.dateTime {
        guard EventKitDateResolver.localDate(from: dateTime, calendar: calendar) != nil else {
          throw ActionExportFailure.invalidDate
        }
        reminder.dueDateComponents = EventKitDateResolver.localDateComponents(
          from: dateTime,
          calendar: calendar
        )
      }
      do {
        try eventStore.save(reminder, commit: true)
      } catch {
        throw ActionExportFailure.saveFailed
      }
      return snapshot(from: reminder, destination: .reminder)

    case .skip:
      throw ActionExportFailure.saveFailed
    }
  }

  func removeItem(
    identifier: String,
    destination: ActionExportDestination,
    expectedMarkerURLString: String
  ) async -> EventKitGatewayRemovalResult {
    guard let item = eventStore.calendarItem(withIdentifier: identifier) else {
      return .missing
    }
    guard item.url?.absoluteString == expectedMarkerURLString else {
      return .markerMismatch
    }

    do {
      switch destination {
      case .calendar:
        guard let event = item as? EKEvent else { return .typeMismatch }
        try eventStore.remove(event, span: .thisEvent, commit: true)
      case .reminder:
        guard let reminder = item as? EKReminder else { return .typeMismatch }
        try eventStore.remove(reminder, commit: true)
      case .skip:
        return .typeMismatch
      }
      return .removed
    } catch {
      return .failed
    }
  }
}

private func snapshot(
  from item: EKCalendarItem,
  destination: ActionExportDestination
) -> EventKitItemSnapshot {
  EventKitItemSnapshot(
    identifier: item.calendarItemIdentifier,
    destination: destination,
    markerURLString: item.url?.absoluteString
  )
}

enum EventKitDateResolver {
  static func localDate(
    from dateTime: ActionDateTime?,
    calendar: Calendar
  ) -> Date? {
    guard let dateTime else { return nil }
    let components = localDateComponents(from: dateTime, calendar: calendar)
    guard let date = calendar.date(from: components) else { return nil }
    let requested: Set<Calendar.Component> =
      dateTime.hasTime
      ? [.year, .month, .day, .hour, .minute]
      : [.year, .month, .day]
    let roundTrip = calendar.dateComponents(requested, from: date)
    guard roundTrip.year == dateTime.year,
      roundTrip.month == dateTime.month,
      roundTrip.day == dateTime.day
    else {
      return nil
    }
    if dateTime.hasTime {
      guard roundTrip.hour == dateTime.hour,
        roundTrip.minute == (dateTime.minute ?? 0)
      else {
        return nil
      }
    }
    return date
  }

  static func localDateComponents(
    from dateTime: ActionDateTime,
    calendar: Calendar
  ) -> DateComponents {
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    components.year = dateTime.year
    components.month = dateTime.month
    components.day = dateTime.day
    if let hour = dateTime.hour {
      components.hour = hour
      components.minute = dateTime.minute ?? 0
    }
    return components
  }
}

private func reminderNotes(for request: ActionExportRequest) -> String? {
  normalized(request.notes)
}

private func normalized(_ value: String?) -> String? {
  guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
    !trimmed.isEmpty
  else {
    return nil
  }
  return trimmed
}

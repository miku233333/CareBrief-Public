import CareBriefCore
import Foundation

public enum ResponsiblePartyValidationIssue: Equatable, Hashable, Sendable {
  case emptyCustomName
  case customNameTooLong(maximum: Int)
}

public enum ResponsibleParty: Equatable, Hashable, Sendable {
  public static let maximumCustomNameLength = 80

  case me
  case familyOrCaregiver
  case custom(String)

  public var displayName: String {
    switch self {
    case .me:
      return "Me"
    case .familyOrCaregiver:
      return "Family / caregiver"
    case .custom(let name):
      return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  public var validationIssue: ResponsiblePartyValidationIssue? {
    guard case .custom(let name) = self else { return nil }
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { return .emptyCustomName }
    guard trimmedName.count <= Self.maximumCustomNameLength else {
      return .customNameTooLong(maximum: Self.maximumCustomNameLength)
    }
    return nil
  }
}

public struct ActionDraft: Equatable, Identifiable, Sendable {
  public var id: String { sourceActionID }

  public let sourceActionID: String
  public var title: String
  public var detail: String
  public var dateTime: ActionDateTime?
  public var location: String?
  public var items: [String]
  public var contact: String?
  public var responsibleParty: ResponsibleParty

  public init(
    sourceActionID: String,
    title: String,
    detail: String,
    dateTime: ActionDateTime?,
    location: String?,
    items: [String],
    contact: String?,
    responsibleParty: ResponsibleParty = .me
  ) {
    self.sourceActionID = sourceActionID
    self.title = title
    self.detail = detail
    self.dateTime = dateTime
    self.location = location
    self.items = items
    self.contact = contact
    self.responsibleParty = responsibleParty
  }

  public init(action: ActionCard) {
    self.init(
      sourceActionID: action.id,
      title: action.title,
      detail: action.detail,
      dateTime: action.dateTime,
      location: action.location,
      items: action.items,
      contact: action.contact
    )
  }
}

public struct ActionDraftGroups: Equatable, Sendable {
  public let today: [ActionDraft]
  public let scheduled: [ActionDraft]
  public let unscheduled: [ActionDraft]

  public init(
    today: [ActionDraft],
    scheduled: [ActionDraft],
    unscheduled: [ActionDraft]
  ) {
    self.today = today
    self.scheduled = scheduled
    self.unscheduled = unscheduled
  }
}

public enum ActionDraftGrouper {
  public static func group(
    _ drafts: [ActionDraft],
    today: Date,
    calendar: Calendar
  ) -> ActionDraftGroups {
    let localCalendar = CareBriefCalendar.localGregorian(timeZone: calendar.timeZone)
    let localToday = localCalendar.dateComponents([.year, .month, .day], from: today)
    var todayDrafts: [ActionDraft] = []
    var scheduledDrafts: [ActionDraft] = []
    var unscheduledDrafts: [ActionDraft] = []

    for draft in drafts {
      guard let dateTime = draft.dateTime, !dateTime.isAmbiguous else {
        unscheduledDrafts.append(draft)
        continue
      }

      if dateTime.year == localToday.year,
        dateTime.month == localToday.month,
        dateTime.day == localToday.day
      {
        todayDrafts.append(draft)
      } else {
        scheduledDrafts.append(draft)
      }
    }

    return ActionDraftGroups(
      today: todayDrafts,
      scheduled: scheduledDrafts,
      unscheduled: unscheduledDrafts
    )
  }
}

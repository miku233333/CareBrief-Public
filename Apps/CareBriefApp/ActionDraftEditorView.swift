import CareBriefAppSupport
import CareBriefCore
import Foundation
import SwiftUI

struct ActionDraftEditorView: View {
  private enum ResponsiblePartyChoice: String, CaseIterable, Identifiable {
    case me
    case familyOrCaregiver
    case custom

    var id: String { rawValue }

    var labelCopy: BilingualCopy {
      switch self {
      case .me: BilingualCopy(primary: "我", secondary: "Me")
      case .familyOrCaregiver:
        BilingualCopy(primary: "家人或照顧者", secondary: "Family / caregiver")
      case .custom: BilingualCopy(primary: "自訂名稱", secondary: "Custom name")
      }
    }
  }

  @Environment(\.dismiss) private var dismiss
  @Environment(\.careBriefEasyReadMode) private var easyReadMode
  @Environment(\.careBriefAppLanguage) private var appLanguage
  @State private var draft: ActionDraft
  @State private var hasDate: Bool
  @State private var hasTime: Bool
  @State private var selectedDay: Date
  @State private var selectedTime: Date
  @State private var dateTimeWasEdited = false
  @State private var dateResolution: ActionDraftDateResolution
  @State private var location: String
  @State private var itemsText: String
  @State private var contact: String
  @State private var responsibleChoice: ResponsiblePartyChoice
  @State private var customResponsibleName: String

  private let originalDateTime: ActionDateTime?
  private let canonicalDefaultTitle: String?
  private let localizedDefaultTitle: String?
  private let onSave: (ActionDraft) -> Void

  init(
    draft: ActionDraft,
    category: ActionCategory? = nil,
    appLanguage: CareBriefAppLanguage = .english,
    onSave: @escaping (ActionDraft) -> Void
  ) {
    let calendar = CareBriefCalendar.localGregorian()
    let initialDate = Self.date(from: draft.dateTime, calendar: calendar) ?? Date()
    var presentedDraft = draft
    let canonicalDefaultTitle: String?
    let localizedDefaultTitle: String?
    if let category,
      CareBriefGeneratedCopy.isDefaultActionTitle(draft.title, for: category)
    {
      canonicalDefaultTitle = CareBriefGeneratedCopy.coreDefaultActionTitle(for: category)
      localizedDefaultTitle = CareBriefGeneratedCopy.actionTitle(
        category: category,
        draftTitle: draft.title,
        language: appLanguage
      )
      presentedDraft.title = localizedDefaultTitle ?? draft.title
    } else {
      canonicalDefaultTitle = nil
      localizedDefaultTitle = nil
    }
    let responsibleChoice: ResponsiblePartyChoice
    let customName: String
    switch draft.responsibleParty {
    case .me:
      responsibleChoice = .me
      customName = ""
    case .familyOrCaregiver:
      responsibleChoice = .familyOrCaregiver
      customName = ""
    case .custom(let name):
      responsibleChoice = .custom
      customName = name
    }

    _draft = State(initialValue: presentedDraft)
    _hasDate = State(initialValue: draft.dateTime != nil)
    _hasTime = State(initialValue: draft.dateTime?.hasTime == true)
    _selectedDay = State(initialValue: initialDate)
    _selectedTime = State(initialValue: initialDate)
    _dateResolution = State(initialValue: ActionDraftDateResolution(dateTime: draft.dateTime))
    _location = State(initialValue: draft.location ?? "")
    _itemsText = State(initialValue: draft.items.joined(separator: "\n"))
    _contact = State(initialValue: draft.contact ?? "")
    _responsibleChoice = State(initialValue: responsibleChoice)
    _customResponsibleName = State(initialValue: customName)
    self.originalDateTime = draft.dateTime
    self.canonicalDefaultTitle = canonicalDefaultTitle
    self.localizedDefaultTitle = localizedDefaultTitle
    self.onSave = onSave
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField(localized("標題", "Title"), text: $draft.title)
            .accessibilityIdentifier("draft.title")
          TextField(localized("詳情", "Details"), text: $draft.detail, axis: .vertical)
            .lineLimit(3...8)
            .accessibilityIdentifier("draft.detail")
        } header: {
          sectionHeader(localized("行動", "Action"), identifier: "draft.section.action")
        }

        Section {
          Toggle(isOn: $hasDate) {
            Text(localized("有日期", "Has a date"))
              .accessibilityIdentifier("draft.hasDateLabel")
          }
          if hasDate {
            DatePicker(localized("日期", "Date"), selection: $selectedDay, displayedComponents: .date)
            Toggle(isOn: $hasTime) {
              Text(localized("包括時間", "Include a time"))
                .accessibilityIdentifier("draft.includeTimeLabel")
            }
            if hasTime {
              DatePicker(
                selection: $selectedTime,
                displayedComponents: .hourAndMinute
              ) {
                Text(localized("時間", "Time"))
                  .accessibilityIdentifier("draft.timeLabel")
              }
            }
          }
          if dateResolution.blocksSave {
            Label(
              easyReadMode
                ? localized(
                  "日期不清楚；加入前請選擇正確日期。",
                  "Date unclear; choose it before adding."
                )
                : localized(
                  "抽取日期仍有歧義；輸出前請明確選擇日期。",
                  "The extracted date is ambiguous; choose the date before export."
                ),
              systemImage: "exclamationmark.triangle.fill"
            )
            .font(.footnote)
            .foregroundStyle(.orange)
            if hasDate {
              Button(localized("使用以上日期", "Use selected date")) {
                dateTimeWasEdited = true
                dateResolution.register(.daySelected)
              }
              .frame(minHeight: 44)
              .accessibilityIdentifier("draft.resolveAmbiguousDate")
            }
          }
        } header: {
          sectionHeader(
            localized("日期及時間", "Date and time"),
            identifier: "draft.section.dateTime"
          )
        }
        .onChange(of: hasDate) { includesDate in
          dateTimeWasEdited = true
          dateResolution.register(.dateAvailability(includesDate))
        }
        .onChange(of: hasTime) { _ in
          dateTimeWasEdited = true
          dateResolution.register(.timeAvailability)
        }
        .onChange(of: selectedDay) { _ in
          dateTimeWasEdited = true
          dateResolution.register(.daySelected)
        }
        .onChange(of: selectedTime) { _ in
          dateTimeWasEdited = true
          dateResolution.register(.timeSelected)
        }

        Section {
          TextField(localized("地點", "Location"), text: $location)
          TextField(
            localized("所需物品，每行一項", "Required items, one per line"),
            text: $itemsText,
            axis: .vertical
          )
          .lineLimit(2...6)
          TextField(localized("聯絡資料", "Contact"), text: $contact)
        } header: {
          sectionHeader(
            localized("實際資料", "Practical details"),
            identifier: "draft.section.practical"
          )
        }

        Section {
          Picker(localized("負責人", "Responsible"), selection: $responsibleChoice) {
            ForEach(ResponsiblePartyChoice.allCases) { choice in
              Text(choice.labelCopy.text(for: appLanguage)).tag(choice)
            }
          }
          if responsibleChoice == .custom {
            TextField(localized("名稱", "Name"), text: $customResponsibleName)
              .accessibilityIdentifier("draft.responsibleName")
            Text(
              easyReadMode
                ? localized(
                  "最多 80 字；不會使用聯絡人或傳送訊息。",
                  "Up to 80 characters; no Contacts or messages."
                )
                : localized(
                  "最多 80 字。CareBrief 不會讀取聯絡人或傳送訊息。",
                  "Up to 80 characters. CareBrief does not use Contacts or send messages."
                )
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            if let issue = responsibleParty.validationIssue {
              Text(issue.copy.text(for: appLanguage))
                .font(.footnote)
              .foregroundStyle(.red)
            }
          }
        } header: {
          sectionHeader(
            localized("負責人", "Responsible person"),
            identifier: "draft.section.responsible"
          )
        }

        Section {
          DisclosureGroup(localized("原文證據保持不變", "Source evidence stays unchanged")) {
            Text(
              easyReadMode
                ? localized(
                  "原文、規則、信心及警告只供查看。",
                  "Quote, rule, confidence, and warnings stay read-only."
                )
                : localized(
                  "修改只影響行動副本及 Calendar／Reminder 預覽；原文、規則、信心及警告保持唯讀。",
                  "Edits affect only the draft and export preview; evidence metadata stays read-only."
                )
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
          }
        }
      }
      .navigationTitle(localized("編輯行動", "Edit action"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(localized("取消", "Cancel")) { dismiss() }
            .tint(Color(uiColor: .label))
            .accessibilityIdentifier("draft.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(localized("儲存", "Save")) { save() }
            .tint(Color(uiColor: .label))
            .disabled(saveDisabled)
            .accessibilityIdentifier("draft.save")
        }
      }
    }
  }

  private var responsibleParty: ResponsibleParty {
    switch responsibleChoice {
    case .me: .me
    case .familyOrCaregiver: .familyOrCaregiver
    case .custom: .custom(customResponsibleName)
    }
  }

  private var saveDisabled: Bool {
    draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || responsibleParty.validationIssue != nil
      || dateResolution.blocksSave
  }

  private func save() {
    let normalizedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalizedTitle == localizedDefaultTitle, let canonicalDefaultTitle {
      draft.title = canonicalDefaultTitle
    } else {
      draft.title = normalizedTitle
    }
    draft.detail = draft.detail.trimmingCharacters(in: .whitespacesAndNewlines)
    draft.location = normalized(location)
    draft.items = itemsText.components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    draft.contact = normalized(contact)
    draft.responsibleParty = responsibleParty
    draft.dateTime = editedDateTime
    onSave(draft)
    dismiss()
  }

  private var editedDateTime: ActionDateTime? {
    guard dateTimeWasEdited else {
      return originalDateTime
    }
    guard !dateResolution.blocksSave else {
      return originalDateTime
    }
    guard hasDate else { return nil }
    let calendar = CareBriefCalendar.localGregorian()
    let dayComponents = calendar.dateComponents(
      [.year, .month, .day],
      from: selectedDay
    )
    let timeComponents = calendar.dateComponents(
      [.hour, .minute],
      from: selectedTime
    )
    guard let year = dayComponents.year,
      let month = dayComponents.month,
      let day = dayComponents.day
    else {
      return nil
    }
    return ActionDateTime(
      year: year,
      month: month,
      day: day,
      hour: hasTime ? timeComponents.hour : nil,
      minute: hasTime ? timeComponents.minute : nil,
      isAmbiguous: false
    )
  }

  private func normalized(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func localized(_ traditionalChinese: String, _ english: String) -> String {
    BilingualCopy(primary: traditionalChinese, secondary: english).text(for: appLanguage)
  }

  private func sectionHeader(_ title: String, identifier: String) -> some View {
    Text(title)
      .foregroundStyle(Color(uiColor: .label))
      .accessibilityIdentifier(identifier)
  }

  private static func date(
    from dateTime: ActionDateTime?,
    calendar: Calendar
  ) -> Date? {
    guard let dateTime else { return nil }
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    components.year = dateTime.year
    components.month = dateTime.month
    components.day = dateTime.day
    components.hour = dateTime.hour ?? 12
    components.minute = dateTime.minute ?? 0
    return calendar.date(from: components)
  }
}

struct ActionDraftDateResolution: Equatable {
  enum Change: Equatable {
    case dateAvailability(Bool)
    case timeAvailability
    case daySelected
    case timeSelected
  }

  private let requiresResolution: Bool
  private(set) var isResolved: Bool

  init(dateTime: ActionDateTime?) {
    requiresResolution = dateTime?.isAmbiguous == true
    isResolved = !requiresResolution
  }

  var blocksSave: Bool {
    requiresResolution && !isResolved
  }

  mutating func register(_ change: Change) {
    guard requiresResolution else { return }
    switch change {
    case .daySelected:
      isResolved = true
    case .dateAvailability(false):
      isResolved = false
    case .dateAvailability(true), .timeAvailability, .timeSelected:
      break
    }
  }
}

extension ResponsiblePartyValidationIssue {
  fileprivate var copy: BilingualCopy {
    switch self {
    case .emptyCustomName:
      return BilingualCopy(
        primary: "請輸入負責人名稱。",
        secondary: "Enter a responsible person's name."
      )
    case .customNameTooLong(let maximum):
      return BilingualCopy(
        primary: "請勿超過 \(maximum) 字。",
        secondary: "Use no more than \(maximum) characters."
      )
    }
  }
}

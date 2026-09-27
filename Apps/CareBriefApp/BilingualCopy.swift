import CareBriefAppSupport
import CareBriefCore
import Foundation
import SwiftUI

enum CareBriefAppLanguage: String, CaseIterable, Identifiable, Sendable {
  case traditionalChinese = "zh-Hant"
  case english = "en"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .traditionalChinese:
      return "繁體中文"
    case .english:
      return "English"
    }
  }

  var locale: Locale {
    Locale(identifier: rawValue)
  }
}

enum CareBriefLanguagePreference: String, CaseIterable, Identifiable, Sendable {
  case system = "system"
  case traditionalChinese = "zh-Hant"
  case english = "en"

  static let storageKey = "carebrief.language.v1"
  static let defaultPreference = CareBriefLanguagePreference.system

  var id: String { rawValue }

  static func current(in defaults: UserDefaults = .standard) -> CareBriefLanguagePreference {
    guard let storedValue = defaults.string(forKey: storageKey) else {
      return defaultPreference
    }

    return CareBriefLanguagePreference(rawValue: storedValue) ?? defaultPreference
  }

  func persist(in defaults: UserDefaults = .standard) {
    defaults.set(rawValue, forKey: Self.storageKey)
  }

  var resolvedLanguage: CareBriefAppLanguage {
    resolvedLanguage(preferredLanguages: Locale.preferredLanguages)
  }

  func resolvedLanguage(preferredLanguages: [String]) -> CareBriefAppLanguage {
    switch self {
    case .traditionalChinese:
      return .traditionalChinese
    case .english:
      return .english
    case .system:
      guard let preferredLanguage = preferredLanguages.first else {
        return .english
      }

      let identifier = preferredLanguage.replacingOccurrences(of: "_", with: "-").lowercased()
      if identifier == "zh-hant" || identifier.hasPrefix("zh-hant-")
        || identifier == "zh-hk" || identifier.hasPrefix("zh-hk-")
        || identifier == "zh-tw" || identifier.hasPrefix("zh-tw-")
      {
        return .traditionalChinese
      }

      return .english
    }
  }
}

struct BilingualCopy: Equatable, Sendable {
  let primary: String
  let secondary: String

  func text(for language: CareBriefAppLanguage) -> String {
    switch language {
    case .traditionalChinese:
      return primary
    case .english:
      return secondary
    }
  }
}

enum CareBriefAccessibilityCopy {
  static func recognizingText(for language: CareBriefAppLanguage) -> String {
    BilingualCopy(
      primary: "正在裝置上辨識文字。",
      secondary: "Recognizing text on this device."
    ).text(for: language)
  }

  static func recognitionCancelled(for language: CareBriefAppLanguage) -> String {
    BilingualCopy(primary: "文字辨識已取消。", secondary: "Text recognition cancelled.")
      .text(for: language)
  }

  static func recognitionFailed(for language: CareBriefAppLanguage) -> String {
    BilingualCopy(primary: "未能辨識文字。", secondary: "Text recognition failed.")
      .text(for: language)
  }

  static func scannerFailed(for language: CareBriefAppLanguage) -> String {
    BilingualCopy(primary: "未能開啟掃描器。", secondary: "Document scanner failed.")
      .text(for: language)
  }

  static func importSummary(
    pageCount: Int,
    for language: CareBriefAppLanguage
  ) -> String {
    BilingualCopy(
      primary: "已匯入 \(pageCount) 頁。請核對文字，再找出行動。",
      secondary:
        "Imported \(pageCount) \(pageCount == 1 ? "page" : "pages"). Review the recognized text, then extract actions."
    ).text(for: language)
  }

  static func importCoverageWarning(
    pageNumbers: [Int],
    for language: CareBriefAppLanguage
  ) -> String {
    let numbers = pageNumbers.map(String.init).joined(separator: ", ")
    let englishPageLabel = pageNumbers.count == 1 ? "page" : "pages"
    return BilingualCopy(
      primary: "第 \(numbers) 頁未辨識到文字，請核對原件。",
      secondary:
        "No text was recognized on \(englishPageLabel) \(numbers). Check the original before extracting actions."
    ).text(for: language)
  }

  static func exportFinished(
    created: Int,
    alreadyAdded: Int,
    failed: Int,
    for language: CareBriefAppLanguage
  ) -> String {
    BilingualCopy(
      primary: "加入完成：新增 \(created) 項，已有 \(alreadyAdded) 項，失敗 \(failed) 項。",
      secondary:
        "Add finished. \(created) added, \(alreadyAdded) already added, \(failed) failed."
    ).text(for: language)
  }

  static func undoFinished(
    removed: Int,
    alreadyRemoved: Int,
    failed: Int,
    for language: CareBriefAppLanguage
  ) -> String {
    BilingualCopy(
      primary: "Undo 完成：移除 \(removed) 項，原已移除 \(alreadyRemoved) 項，失敗 \(failed) 項。",
      secondary:
        "Undo finished. \(removed) removed, \(alreadyRemoved) already removed, \(failed) failed."
    ).text(for: language)
  }
}

enum CareBriefGeneratedCopy {
  static func actionTitle(
    category: ActionCategory,
    draftTitle: String,
    language: CareBriefAppLanguage
  ) -> String {
    guard isDefaultActionTitle(draftTitle, for: category) else { return draftTitle }
    return actionTitleCopy(for: category).text(for: language)
  }

  static func exportPresentation(
    category: ActionCategory,
    draftTitle: String,
    language: CareBriefAppLanguage
  ) -> ActionExportPresentation {
    switch language {
    case .traditionalChinese:
      return ActionExportPresentation(
        title: actionTitle(category: category, draftTitle: draftTitle, language: language),
        bringLabel: "要帶",
        contactLabel: "聯絡",
        locationLabel: "地點",
        responsibleLabel: "負責人",
        meLabel: "我",
        familyOrCaregiverLabel: "家人或照顧者",
        separator: "："
      )
    case .english:
      return ActionExportPresentation(
        title: actionTitle(category: category, draftTitle: draftTitle, language: language)
      )
    }
  }

  static func warning(_ warning: String, language: CareBriefAppLanguage) -> String {
    guard language == .traditionalChinese else { return warning }
    switch warning {
    case "No supported actionable instruction was found. Review the source document manually.":
      return "未找到支援的行動指示，請按原文自行核對。"
    case "Multiple dates or times occur in one source segment; no single structured date was selected.":
      return "同一段原文有多個日期或時間，未有自動選擇日期。"
    case "A cancelled, rescheduled, or negated appointment was detected; no active appointment action was emitted.":
      return "偵測到已取消、改期或否定的預約，未建立有效預約行動。"
    case "An appointment keyword and date were found without a clear action-date relationship; no appointment action was emitted.":
      return "找到預約字眼及日期，但兩者關係不清楚，未建立預約行動。"
    case "A negated submission or deadline instruction was detected; no positive deadline or next-step action was emitted.":
      return "偵測到否定的提交或限期指示，未建立限期或下一步行動。"
    case "A deadline keyword and date were found without a clear due-date relationship; no deadline action was emitted.":
      return "找到限期字眼及日期，但到期關係不清楚，未建立限期行動。"
    case "A negated preparation instruction was detected; no positive preparation action was emitted.":
      return "偵測到否定的準備指示，未建立準備行動。"
    case "A negated bring instruction was detected; no required-item action was emitted.":
      return "偵測到否定的攜帶指示，未建立所需物品行動。"
    case "A negated contact instruction was detected; no positive contact action was emitted.":
      return "偵測到否定的聯絡指示，未建立聯絡行動。"
    case "A date or time may be present but was not explicit enough to parse safely.":
      return "原文可能有日期或時間，但未夠明確，無法安全辨識。"
    case "One or more actions reference a different source document and require review.":
      return "一項或以上行動指向另一份來源文件，必須重新核對。"
    default:
      return "抽取時有警告，請按原文逐項核對。"
    }
  }

  static func importError(_ message: String, language: CareBriefAppLanguage) -> String {
    guard language == .traditionalChinese else { return message }
    switch message {
    case "CareBrief could not open that image. Try another photo.":
      return "未能開啟相片，請選擇另一張相片。"
    case "That image is too large to process safely. Choose a standard photo under 50 MB.":
      return "相片太大，請選擇 50 MB 以下的普通相片。"
    case "Traditional Chinese and English text recognition is unavailable on this device.":
      return "此裝置未能使用繁體中文及英文文字辨識。"
    case "CareBrief could not find readable text in that image.":
      return "相片內找不到清晰文字。請換一張較清楚的相片。"
    case "Text recognition did not finish. Try again with a clearer image.":
      return "文字辨識未完成，請用較清楚的相片再試。"
    case "The document scanner did not finish. Try again or choose a photo.":
      return "文件掃描未完成，請再試或改為選擇相片。"
    default:
      return "未能讀取文件，請再試。"
    }
  }

  static func isDefaultActionTitle(_ title: String, for category: ActionCategory) -> Bool {
    normalized(title) == coreDefaultActionTitle(for: category)
  }

  static func coreDefaultActionTitle(for category: ActionCategory) -> String {
    switch category {
    case .appointment: "Appointment"
    case .deadline: "Deadline"
    case .preparation: "Preparation"
    case .requiredItem: "Bring"
    case .contact: "Contact"
    case .nextStep: "Next step"
    case .location: "Location"
    }
  }

  private static func actionTitleCopy(for category: ActionCategory) -> BilingualCopy {
    switch category {
    case .appointment: BilingualCopy(primary: "覆診／預約", secondary: "Appointment")
    case .deadline: BilingualCopy(primary: "限期", secondary: "Deadline")
    case .preparation: BilingualCopy(primary: "準備", secondary: "Preparation")
    case .requiredItem: BilingualCopy(primary: "要帶物品", secondary: "Required item")
    case .contact: BilingualCopy(primary: "聯絡", secondary: "Contact")
    case .nextStep: BilingualCopy(primary: "下一步", secondary: "Next step")
    case .location: BilingualCopy(primary: "地點", secondary: "Location")
    }
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
      .precomposedStringWithCanonicalMapping
  }
}

extension CareBriefLanguagePreference {
  var displayCopy: BilingualCopy {
    switch self {
    case .system:
      return BilingualCopy(primary: "跟隨 iPhone", secondary: "Follow iPhone")
    case .traditionalChinese:
      return BilingualCopy(primary: "繁體中文", secondary: "Traditional Chinese")
    case .english:
      return BilingualCopy(primary: "英文", secondary: "English")
    }
  }
}

private struct CareBriefAppLanguageEnvironmentKey: EnvironmentKey {
  static let defaultValue = CareBriefLanguagePreference.system.resolvedLanguage
}

extension EnvironmentValues {
  var careBriefAppLanguage: CareBriefAppLanguage {
    get { self[CareBriefAppLanguageEnvironmentKey.self] }
    set { self[CareBriefAppLanguageEnvironmentKey.self] = newValue }
  }
}

enum BilingualLabelStyle: Sendable {
  case body
  case headline
  case explanation
}

struct BilingualLabel: View {
  @Environment(\.careBriefAppLanguage) private var language

  let copy: BilingualCopy
  let style: BilingualLabelStyle

  init(_ copy: BilingualCopy, style: BilingualLabelStyle = .body) {
    self.copy = copy
    self.style = style
  }

  var body: some View {
    Text(copy.text(for: language))
      .font(font)
      .foregroundStyle(foregroundColor)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var font: Font {
    switch style {
    case .body:
      return .body
    case .headline:
      return .headline
    case .explanation:
      return .subheadline
    }
  }

  private var foregroundColor: Color {
    switch style {
    case .body, .headline:
      return .primary
    case .explanation:
      return .secondary
    }
  }
}

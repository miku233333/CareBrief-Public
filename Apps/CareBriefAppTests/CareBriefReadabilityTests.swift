import Foundation
import SwiftUI
import Testing

@testable import CareBrief

@Suite struct CareBriefAppLanguageTests {
  @Test func storageContractDefaultsToTheIPhoneLanguage() {
    #expect(CareBriefLanguagePreference.storageKey == "carebrief.language.v1")
    #expect(CareBriefLanguagePreference.defaultPreference == .system)
    #expect(CareBriefLanguagePreference.system.rawValue == "system")
    #expect(CareBriefLanguagePreference.traditionalChinese.rawValue == "zh-Hant")
    #expect(CareBriefLanguagePreference.english.rawValue == "en")
  }

  @Test func storedPreferencePersistsAndUnknownValuesFallBackSafely() {
    let suiteName = "CareBriefAppLanguageTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    #expect(CareBriefLanguagePreference.current(in: defaults) == .system)

    CareBriefLanguagePreference.english.persist(in: defaults)
    #expect(CareBriefLanguagePreference.current(in: defaults) == .english)

    defaults.set("unsupported-language", forKey: CareBriefLanguagePreference.storageKey)
    #expect(CareBriefLanguagePreference.current(in: defaults) == .system)
  }

  @Test func systemPreferenceRecognizesTraditionalChineseIPhoneLanguages() {
    for identifier in ["zh-Hant", "zh-Hant-HK", "zh-HK", "zh-TW", "zh_HK"] {
      #expect(
        CareBriefLanguagePreference.system.resolvedLanguage(
          preferredLanguages: [identifier]
        ) == .traditionalChinese
      )
    }
  }

  @Test func systemPreferenceUsesEnglishForOtherOrMissingLanguages() {
    for preferredLanguages in [["en-HK"], ["zh-Hans"], ["ja-JP"], []] {
      #expect(
        CareBriefLanguagePreference.system.resolvedLanguage(
          preferredLanguages: preferredLanguages
        ) == .english
      )
    }
  }

  @Test func manualPreferenceOverridesTheIPhoneLanguage() {
    #expect(
      CareBriefLanguagePreference.traditionalChinese.resolvedLanguage(
        preferredLanguages: ["en-US"]
      ) == .traditionalChinese
    )
    #expect(
      CareBriefLanguagePreference.english.resolvedLanguage(
        preferredLanguages: ["zh-HK"]
      ) == .english
    )
  }

  @Test func selectedLanguageReturnsOneLocalizedString() {
    let copy = BilingualCopy(primary: "設定", secondary: "Settings")

    #expect(copy.text(for: .traditionalChinese) == "設定")
    #expect(copy.text(for: .english) == "Settings")
    #expect(CareBriefAppLanguage.traditionalChinese.displayName == "繁體中文")
    #expect(CareBriefAppLanguage.english.displayName == "English")
  }

  @Test func selectedLanguageSuppliesTheMatchingSwiftUILocale() {
    #expect(CareBriefAppLanguage.traditionalChinese.locale.identifier == "zh-Hant")
    #expect(CareBriefAppLanguage.english.locale.identifier == "en")
  }

  @Test func accessibilityAnnouncementsUseTheSelectedLanguage() {
    #expect(
      CareBriefAccessibilityCopy.recognizingText(for: .traditionalChinese)
        == "正在裝置上辨識文字。"
    )
    #expect(
      CareBriefAccessibilityCopy.importSummary(pageCount: 2, for: .english)
        == "Imported 2 pages. Review the recognized text, then extract actions."
    )
    #expect(
      CareBriefAccessibilityCopy.exportFinished(
        created: 1,
        alreadyAdded: 2,
        failed: 3,
        for: .traditionalChinese
      ) == "加入完成：新增 1 項，已有 2 項，失敗 3 項。"
    )
  }

  @Test func swiftUIEnvironmentDefaultsToTheResolvedIPhoneLanguage() {
    #expect(
      EnvironmentValues().careBriefAppLanguage
        == CareBriefLanguagePreference.system.resolvedLanguage
    )
  }
}

@Suite struct CareBriefReadabilityTests {
  @Test func storageKeyAndDefaultsRemainStable() {
    #expect(CareBriefReadability.storageKey == "carebrief.easyReadMode")
    #expect(CareBriefReadability.defaultIsEasyReadEnabled)
  }

  @Test func easyReadIsTheDefaultAndAStoredOffChoiceWins() {
    let suiteName = "CareBriefReadabilityTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    #expect(CareBriefReadability.isEasyReadEnabled(in: defaults))

    defaults.set(false, forKey: CareBriefReadability.storageKey)

    #expect(!CareBriefReadability.isEasyReadEnabled(in: defaults))

    defaults.set(true, forKey: CareBriefReadability.storageKey)

    #expect(CareBriefReadability.isEasyReadEnabled(in: defaults))
  }

  @Test func shortCopyKeepsSafetyBoundariesVisible() {
    #expect(CareBriefReadability.documentPrivacyText(isEasyRead: true).contains("no upload"))
    #expect(CareBriefReadability.documentPrivacyText(isEasyRead: true).contains("discarded"))
    #expect(CareBriefReadability.noActionsText(isEasyRead: true).contains("did not guess"))
    #expect(CareBriefReadability.eventKitPermissionText(isEasyRead: true).contains("Full access"))
    #expect(CareBriefReadability.eventKitPermissionText(isEasyRead: true).contains("after Add"))
  }

  @Test func easyReadChangesCopyAndDisclosureOnly() {
    let easyCopy = CareBriefReadability.modeCopy(isEasyRead: true)
    let fullCopy = CareBriefReadability.modeCopy(isEasyRead: false)

    #expect(easyCopy.primary == "簡短內容，技術細節會收起。")
    #expect(easyCopy.secondary.contains("technical details collapsed"))
    #expect(fullCopy.primary == "顯示完整指引及技術細節。")
    #expect(!CareBriefReadability.showsTechnicalDetailsByDefault(isEasyRead: true))
    #expect(CareBriefReadability.showsTechnicalDetailsByDefault(isEasyRead: false))
    #expect(!easyCopy.primary.localizedCaseInsensitiveContains("larger"))
    #expect(!easyCopy.secondary.localizedCaseInsensitiveContains("larger"))
  }

  @Test func accessibilityTextSizesUseStackedActionControls() {
    #expect(!CareBriefAdaptiveLayout.usesStackedActionControls(at: .large))
    #expect(
      !CareBriefAdaptiveLayout.usesStackedActionControls(at: .xxxLarge)
    )

    for size in [
      DynamicTypeSize.accessibility1,
      .accessibility2,
      .accessibility3,
      .accessibility4,
      .accessibility5,
    ] {
      #expect(CareBriefAdaptiveLayout.usesStackedActionControls(at: size))
    }
  }

  @Test func accessibilityTextSizesAllowActionLabelsToWrap() {
    #expect(CareBriefAdaptiveLayout.keepsActionLabelOnSingleLine(at: .large))
    #expect(
      !CareBriefAdaptiveLayout.keepsActionLabelOnSingleLine(at: .accessibility5)
    )
  }
}

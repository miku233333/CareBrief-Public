import Foundation
import SwiftUI

enum CareBriefAdaptiveLayout {
  static func usesStackedActionControls(at dynamicTypeSize: DynamicTypeSize) -> Bool {
    dynamicTypeSize.isAccessibilitySize
  }

  static func keepsActionLabelOnSingleLine(at dynamicTypeSize: DynamicTypeSize) -> Bool {
    !dynamicTypeSize.isAccessibilitySize
  }
}

enum CareBriefReadability {
  static let storageKey = "carebrief.easyReadMode"
  static let defaultIsEasyReadEnabled = true

  static func isEasyReadEnabled(in defaults: UserDefaults) -> Bool {
    guard defaults.object(forKey: storageKey) != nil else {
      return defaultIsEasyReadEnabled
    }
    return defaults.bool(forKey: storageKey)
  }

  static func modeCopy(isEasyRead: Bool) -> BilingualCopy {
    if isEasyRead {
      return BilingualCopy(
        primary: "簡短內容，技術細節會收起。",
        secondary: "Shorter copy with technical details collapsed."
      )
    }
    return BilingualCopy(
      primary: "顯示完整指引及技術細節。",
      secondary: "Show full guidance and technical details."
    )
  }

  static func modeDescriptionCopy(isEasyRead: Bool) -> BilingualCopy {
    modeCopy(isEasyRead: isEasyRead)
  }

  static func showsTechnicalDetailsByDefault(isEasyRead: Bool) -> Bool {
    !isEasyRead
  }

  static func modeDescription(
    isEasyRead: Bool,
    language: CareBriefAppLanguage = .english
  ) -> String {
    modeCopy(isEasyRead: isEasyRead).text(for: language)
  }

  static func documentPrivacyCopy(isEasyRead: Bool) -> BilingualCopy {
    if isEasyRead {
      return BilingualCopy(
        primary: "私隱：不會上載。OCR 後會丟棄來源圖片；沒有帳戶或分析。",
        secondary:
          "Private: no upload. The source image is discarded after OCR; no account or analytics."
      )
    }
    return BilingualCopy(
      primary: "CareBrief 在裝置上處理圖片，不會上載，OCR 後亦不保留來源圖片。服務不使用帳戶、分析或 API key。",
      secondary:
        "CareBrief processes images on device, does not upload them, and does not retain source images after OCR. No account, analytics, or API key is used."
    )
  }

  static func documentPrivacyText(
    isEasyRead: Bool,
    language: CareBriefAppLanguage = .english
  ) -> String {
    documentPrivacyCopy(isEasyRead: isEasyRead).text(for: language)
  }

  static func noActionsCopy(isEasyRead: Bool) -> BilingualCopy {
    if isEasyRead {
      return BilingualCopy(
        primary: "找不到明確行動，所以 CareBrief 沒有猜測。請對照原文。",
        secondary: "No clear action found, so CareBrief did not guess. Check the source."
      )
    }
    return BilingualCopy(
      primary: "請自行核對原文。當規則未能確定時，CareBrief 不會自行建立行動。",
      secondary:
        "Review the source manually. CareBrief does not invent an action when the rule set is unsure."
    )
  }

  static func noActionsText(
    isEasyRead: Bool,
    language: CareBriefAppLanguage = .english
  ) -> String {
    noActionsCopy(isEasyRead: isEasyRead).text(for: language)
  }

  static func eventKitPermissionCopy(isEasyRead: Bool) -> BilingualCopy {
    if isEasyRead {
      return BilingualCopy(
        primary: "只會在按「加入」後，為你選擇的 Apple App 要求完整取用權限。",
        secondary: "Full access is asked only after Add, for the Apple apps selected below."
      )
    }
    return BilingualCopy(
      primary: "只會在按「加入」後，按下方實際選擇的目的地要求完整取用權限。",
      secondary:
        "Full access is requested only after Add, and only for destinations selected below."
    )
  }

  static func eventKitPermissionText(
    isEasyRead: Bool,
    language: CareBriefAppLanguage = .english
  ) -> String {
    eventKitPermissionCopy(isEasyRead: isEasyRead).text(for: language)
  }
}

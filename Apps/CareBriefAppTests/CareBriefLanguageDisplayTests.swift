import CareBriefCore
import Testing

@testable import CareBrief

@Suite struct CareBriefLanguageDisplayTests {
  @Test func actionDateUsesTheSelectedAppLanguage() throws {
    let dateTime = try #require(ActionDateTime(year: 2026, month: 8, day: 15, hour: 9))

    let traditionalChinese = dateTime.localizedCareBriefDisplay(for: .traditionalChinese)
    let english = dateTime.localizedCareBriefDisplay(for: .english)

    #expect(traditionalChinese.contains("8月15"))
    #expect(!traditionalChinese.contains("Aug"))
    #expect(english.contains("Aug"))
    #expect(!english.contains("月"))
  }

  @Test func generatedActionTitlesFollowTheSelectedLanguageButUserTitlesStayVerbatim() {
    #expect(
      CareBriefGeneratedCopy.actionTitle(
        category: .requiredItem,
        draftTitle: "Bring",
        language: .traditionalChinese
      ) == "要帶物品"
    )
    #expect(
      CareBriefGeneratedCopy.actionTitle(
        category: .requiredItem,
        draftTitle: "Bring",
        language: .english
      ) == "Required item"
    )
    #expect(
      CareBriefGeneratedCopy.actionTitle(
        category: .requiredItem,
        draftTitle: "帶媽媽的覆診紙",
        language: .english
      ) == "帶媽媽的覆診紙"
    )
  }

  @Test func extractorWarningsAndImportErrorsFollowTheSelectedLanguage() {
    let warning =
      "Multiple dates or times occur in one source segment; no single structured date was selected."
    let importError = "CareBrief could not find readable text in that image."

    #expect(
      CareBriefGeneratedCopy.warning(warning, language: .traditionalChinese)
        == "同一段原文有多個日期或時間，未有自動選擇日期。"
    )
    #expect(CareBriefGeneratedCopy.warning(warning, language: .english) == warning)
    #expect(
      CareBriefGeneratedCopy.importError(importError, language: .traditionalChinese)
        == "相片內找不到清晰文字。請換一張較清楚的相片。"
    )
    #expect(CareBriefGeneratedCopy.importError(importError, language: .english) == importError)
  }

  @Test func exportPresentationUsesOnlyTheSelectedLanguage() {
    let traditionalChinese = CareBriefGeneratedCopy.exportPresentation(
      category: .requiredItem,
      draftTitle: "Bring",
      language: .traditionalChinese
    )
    let english = CareBriefGeneratedCopy.exportPresentation(
      category: .requiredItem,
      draftTitle: "Bring",
      language: .english
    )

    #expect(traditionalChinese.title == "要帶物品")
    #expect(traditionalChinese.bringLabel == "要帶")
    #expect(traditionalChinese.familyOrCaregiverLabel == "家人或照顧者")
    #expect(traditionalChinese.separator == "：")
    #expect(english.title == "Required item")
    #expect(english.bringLabel == "Bring")
    #expect(english.separator == ": ")
  }
}

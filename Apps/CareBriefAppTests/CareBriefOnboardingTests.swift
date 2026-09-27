import CareBriefAppSupport
import Foundation
import Testing

@testable import CareBrief

@Suite struct CareBriefOnboardingTests {
  @Test func storageKeyAndDefaultRemainVersionedAndIndependent() {
    #expect(
      CareBriefOnboardingPreferences.storageKey
        == "carebrief.onboarding.v1.completed"
    )
    #expect(!CareBriefOnboardingPreferences.defaultIsCompleted)
    #expect(
      CareBriefOnboardingPreferences.storageKey
        != CareBriefReadability.storageKey
    )
  }

  @Test func firstLaunchDefaultsToIncompleteAndCompletionSurvivesRelaunch() {
    let suiteName = "CareBriefOnboardingTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    #expect(!CareBriefOnboardingPreferences.isCompleted(in: defaults))

    CareBriefOnboardingPreferences.markCompleted(in: defaults)

    #expect(CareBriefOnboardingPreferences.isCompleted(in: defaults))
  }

  @Test func theThreePagesProvideCompleteChineseAndEnglishCopy() {
    let pages = CareBriefOnboardingPage.all

    #expect(pages.count == 3)
    #expect(
      pages.map { $0.title.text(for: .traditionalChinese) }
        == ["掃描或選相片", "對照原文", "確認後先加入"]
    )
    #expect(
      pages.map { $0.title.text(for: .english) } == [
        "Scan or choose a photo", "Check the source", "Add after confirmation",
      ])
    #expect(
      pages.allSatisfy {
        !$0.detail.text(for: .traditionalChinese).isEmpty
          && !$0.detail.text(for: .english).isEmpty
      }
    )
    #expect(pages.allSatisfy { !$0.symbolName.isEmpty })
  }

  @Test func navigationCopySupportsTheSelectedLanguage() {
    #expect(
      CareBriefOnboardingCopy.skip.text(for: .traditionalChinese) == "跳過"
    )
    #expect(CareBriefOnboardingCopy.skip.text(for: .english) == "Skip")
    #expect(
      CareBriefOnboardingCopy.back.text(for: .traditionalChinese) == "返回"
    )
    #expect(CareBriefOnboardingCopy.back.text(for: .english) == "Back")
    #expect(
      CareBriefOnboardingCopy.next.text(for: .traditionalChinese) == "下一步"
    )
    #expect(CareBriefOnboardingCopy.next.text(for: .english) == "Next")
    #expect(
      CareBriefOnboardingCopy.start.text(for: .traditionalChinese) == "開始使用"
    )
    #expect(CareBriefOnboardingCopy.start.text(for: .english) == "Start")
  }

  @Test func languageControlOffersSystemChineseAndEnglish() {
    #expect(CareBriefLanguagePreference.defaultPreference == .system)
    #expect(
      CareBriefLanguagePreference.allCases
        == [.system, .traditionalChinese, .english]
    )
    #expect(
      CareBriefLanguagePreference.system.displayCopy.text(
        for: .traditionalChinese
      ) == "跟隨 iPhone"
    )
    #expect(
      CareBriefLanguagePreference.system.displayCopy.text(for: .english)
        == "Follow iPhone"
    )
  }

  @Test func changingLanguageDoesNotResetPageOrCompletion() {
    var flow = CareBriefOnboardingFlow(mode: .firstLaunch)
    _ = flow.moveNext()
    let pageBeforeSwitch = flow.currentPageIndex
    let completionBeforeSwitch = CareBriefOnboardingPreferences.completionValue(
      current: false,
      after: nil
    )

    var preference = CareBriefLanguagePreference.traditionalChinese
    #expect(
      flow.currentPage.title.text(for: preference.resolvedLanguage) == "對照原文"
    )
    preference = .english

    #expect(
      flow.currentPage.title.text(for: preference.resolvedLanguage)
        == "Check the source"
    )
    #expect(flow.currentPageIndex == pageBeforeSwitch)
    #expect(
      CareBriefOnboardingPreferences.completionValue(current: false, after: nil)
        == completionBeforeSwitch
    )
  }

  @Test func firstLaunchSkipOrFinalStartCompletesTheOnboarding() {
    let skipped = CareBriefOnboardingFlow(mode: .firstLaunch)
    #expect(skipped.skip() == .completed)

    var finished = CareBriefOnboardingFlow(mode: .firstLaunch)
    #expect(finished.moveNext() == nil)
    #expect(finished.moveNext() == nil)
    #expect(finished.moveNext() == .completed)
  }

  @Test func backNavigationStopsAtTheFirstPage() {
    var flow = CareBriefOnboardingFlow(mode: .firstLaunch)

    flow.moveBack()
    #expect(flow.currentPageIndex == 0)
    _ = flow.moveNext()
    flow.moveBack()
    #expect(flow.currentPageIndex == 0)
  }

  @Test func abortingDoesNotCompleteAndReplayNeverChangesCompletion() {
    var interrupted = CareBriefOnboardingFlow(mode: .firstLaunch)
    _ = interrupted.moveNext()

    #expect(
      CareBriefOnboardingPreferences.completionValue(current: false, after: nil) == false)

    let relaunched = CareBriefOnboardingFlow(mode: .firstLaunch)
    #expect(relaunched.currentPageIndex == 0)

    var replay = CareBriefOnboardingFlow(mode: .replay)
    #expect(replay.currentPageIndex == 0)
    #expect(replay.skip() == .dismissedReplay)
    #expect(
      CareBriefOnboardingPreferences.completionValue(
        current: true,
        after: replay.skip()
      ))

    _ = replay.moveNext()
    _ = replay.moveNext()
    let replayFinish = replay.moveNext()
    #expect(replayFinish == .dismissedReplay)
    #expect(
      CareBriefOnboardingPreferences.completionValue(
        current: true,
        after: replayFinish
      ))
    #expect(
      !CareBriefOnboardingPreferences.completionValue(
        current: false,
        after: replayFinish
      ))
  }

  @MainActor
  @Test func replayReadabilityAndLanguageChangesDoNotResetReviewOrExportState() async throws {
    let viewModel = CareBriefViewModel(exporter: ReplayStateExporter())
    viewModel.loadSample()
    viewModel.extract()
    let action = try #require(viewModel.actions.first)
    viewModel.setConfirmation(true, forActionID: action.id)
    viewModel.prepareExportPreview()
    await viewModel.addPreparedActions(acknowledgesReviewWarnings: true)

    let input = viewModel.inputText
    let drafts = viewModel.reviewState.drafts
    let confirmations = viewModel.reviewState.confirmedActionIDs
    let preview = viewModel.exportPreview
    let receipt = try #require(viewModel.latestExportReceipt)

    let rootSession = CareBriefRootSession(viewModel: viewModel)
    rootSession.beginOnboardingReplay()
    #expect(rootSession.isReplayingOnboarding)
    rootSession.finishOnboardingReplay()
    #expect(!rootSession.isReplayingOnboarding)
    #expect(rootSession.viewModel === viewModel)

    viewModel.setAppLanguage(.traditionalChinese)
    #expect(viewModel.appLanguage == .traditionalChinese)

    let suiteName = "CareBriefOnboardingState.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(false, forKey: CareBriefReadability.storageKey)

    #expect(viewModel.inputText == input)
    #expect(viewModel.reviewState.drafts == drafts)
    #expect(viewModel.reviewState.confirmedActionIDs == confirmations)
    #expect(viewModel.exportPreview == preview)
    #expect(viewModel.latestExportReceipt == receipt)
  }
}

@MainActor
private final class ReplayStateExporter: ActionExporting {
  func export(_ requests: [ActionExportRequest]) async -> ActionExportBatchResult {
    ActionExportBatchResult(
      results: requests.map { request in
        ActionExportItemResult(
          actionID: request.actionID,
          outcome: .created(
            ExportReceiptItem(
              actionID: request.actionID,
              destination: request.destination,
              calendarItemIdentifier: "replay-state-\(request.actionID)",
              markerURLString: "carebrief://export/v1/calendar/replay-state",
              dateTime: request.dateTime
            )
          )
        )
      }
    )
  }

  func undo(_ receipt: ExportReceipt) async -> ActionUndoBatchResult {
    ActionUndoBatchResult(operationID: receipt.operationID, results: [])
  }
}

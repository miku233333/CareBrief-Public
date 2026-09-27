import Foundation
import SwiftUI

enum CareBriefOnboardingPreferences {
  static let storageKey = "carebrief.onboarding.v1.completed"
  static let defaultIsCompleted = false

  static func isCompleted(in defaults: UserDefaults) -> Bool {
    guard defaults.object(forKey: storageKey) != nil else {
      return defaultIsCompleted
    }
    return defaults.bool(forKey: storageKey)
  }

  static func markCompleted(in defaults: UserDefaults) {
    defaults.set(true, forKey: storageKey)
  }

  static func completionValue(
    current: Bool,
    after exit: CareBriefOnboardingExit?
  ) -> Bool {
    exit == .completed ? true : current
  }
}

struct CareBriefOnboardingPage: Equatable, Identifiable, Sendable {
  let id: Int
  let symbolName: String
  let title: BilingualCopy
  let detail: BilingualCopy

  static let all: [Self] = [
    CareBriefOnboardingPage(
      id: 0,
      symbolName: "doc.viewfinder",
      title: BilingualCopy(
        primary: "掃描或選相片",
        secondary: "Scan or choose a photo"
      ),
      detail: BilingualCopy(
        primary: "拍攝或選擇醫院及政府文件。文字只會在這部裝置上辨認。",
        secondary:
          "Scan or choose a hospital or government document. Text recognition stays on this device."
      )
    ),
    CareBriefOnboardingPage(
      id: 1,
      symbolName: "text.document",
      title: BilingualCopy(
        primary: "對照原文",
        secondary: "Check the source"
      ),
      detail: BilingualCopy(
        primary: "先查看原文證據，再編輯日期、地點和負責人。CareBrief 不會作醫療判斷。",
        secondary:
          "Check the source evidence before editing dates, places, and responsibility. CareBrief does not make medical decisions."
      )
    ),
    CareBriefOnboardingPage(
      id: 2,
      symbolName: "checkmark.circle",
      title: BilingualCopy(
        primary: "確認後先加入",
        secondary: "Add after confirmation"
      ),
      detail: BilingualCopy(
        primary: "核對行動後才可預覽。只有按「加入」時，才會要求 Calendar 或 Reminders 權限。",
        secondary:
          "Preview only checked actions. Calendar or Reminders access is requested only when you tap Add."
      )
    ),
  ]
}

enum CareBriefOnboardingCopy {
  static let language = BilingualCopy(primary: "顯示語言", secondary: "Display language")
  static let skip = BilingualCopy(primary: "跳過", secondary: "Skip")
  static let back = BilingualCopy(primary: "返回", secondary: "Back")
  static let next = BilingualCopy(primary: "下一步", secondary: "Next")
  static let start = BilingualCopy(primary: "開始使用", secondary: "Start")
}

enum CareBriefOnboardingMode: Equatable, Sendable {
  case firstLaunch
  case replay

  fileprivate var exit: CareBriefOnboardingExit {
    switch self {
    case .firstLaunch:
      return .completed
    case .replay:
      return .dismissedReplay
    }
  }
}

enum CareBriefOnboardingExit: Equatable, Sendable {
  case completed
  case dismissedReplay
}

struct CareBriefOnboardingFlow: Equatable, Sendable {
  let mode: CareBriefOnboardingMode
  private(set) var currentPageIndex = 0

  var currentPage: CareBriefOnboardingPage {
    CareBriefOnboardingPage.all[currentPageIndex]
  }

  var isFirstPage: Bool {
    currentPageIndex == 0
  }

  var isLastPage: Bool {
    currentPageIndex == CareBriefOnboardingPage.all.count - 1
  }

  mutating func move(to pageIndex: Int) {
    currentPageIndex = min(
      max(pageIndex, 0),
      CareBriefOnboardingPage.all.count - 1
    )
  }

  mutating func moveBack() {
    move(to: currentPageIndex - 1)
  }

  mutating func moveNext() -> CareBriefOnboardingExit? {
    guard isLastPage else {
      move(to: currentPageIndex + 1)
      return nil
    }
    return mode.exit
  }

  func skip() -> CareBriefOnboardingExit {
    mode.exit
  }
}

struct CareBriefOnboardingView: View {
  let onExit: (CareBriefOnboardingExit) -> Void

  @Binding private var languagePreference: CareBriefLanguagePreference
  @State private var flow: CareBriefOnboardingFlow

  init(
    languagePreference: Binding<CareBriefLanguagePreference>,
    mode: CareBriefOnboardingMode,
    onExit: @escaping (CareBriefOnboardingExit) -> Void
  ) {
    self.onExit = onExit
    _languagePreference = languagePreference
    _flow = State(initialValue: CareBriefOnboardingFlow(mode: mode))
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        TabView(selection: pageSelection) {
          ForEach(CareBriefOnboardingPage.all) { page in
            onboardingPage(page)
              .tag(page.id)
          }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))

        Divider()
        navigationControls
      }
      .navigationTitle("CareBrief")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          languagePicker
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          Button(CareBriefOnboardingCopy.skip.text(for: language)) {
            onExit(flow.skip())
          }
          .frame(minWidth: 44, minHeight: 44)
          .contentShape(Rectangle())
          .accessibilityIdentifier("carebrief.onboarding.skip")
        }
      }
    }
    .environment(\.careBriefAppLanguage, language)
  }

  private var language: CareBriefAppLanguage {
    languagePreference.resolvedLanguage
  }

  private var languagePicker: some View {
    Menu {
      ForEach(CareBriefLanguagePreference.allCases, id: \.self) { preference in
        Button {
          languagePreference = preference
        } label: {
          if preference == languagePreference {
            Label(
              preference.displayCopy.text(for: language),
              systemImage: "checkmark"
            )
          } else {
            Text(preference.displayCopy.text(for: language))
          }
        }
      }
    } label: {
      Image(systemName: "globe")
    }
    .frame(minWidth: 44, minHeight: 44)
    .contentShape(Rectangle())
    .accessibilityLabel(CareBriefOnboardingCopy.language.text(for: language))
    .accessibilityIdentifier("carebrief.onboarding.language")
  }

  private var pageSelection: Binding<Int> {
    Binding(
      get: { flow.currentPageIndex },
      set: { flow.move(to: $0) }
    )
  }

  private func onboardingPage(_ page: CareBriefOnboardingPage) -> some View {
    ScrollView {
      VStack(alignment: .leading) {
        Image(systemName: page.symbolName)
          .font(.largeTitle)
          .foregroundStyle(.tint)
          .accessibilityHidden(true)

        BilingualLabel(page.title, style: .headline)
        BilingualLabel(page.detail, style: .body)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
    }
    .accessibilityIdentifier("carebrief.onboarding.page.\(page.id + 1)")
  }

  private var navigationControls: some View {
    ViewThatFits(in: .horizontal) {
      HStack {
        backButton
        Spacer()
        primaryButton
      }
      VStack(alignment: .leading) {
        primaryButton
          .frame(maxWidth: .infinity)
        backButton
      }
    }
    .padding()
  }

  @ViewBuilder private var backButton: some View {
    if !flow.isFirstPage {
      Button(CareBriefOnboardingCopy.back.text(for: language)) {
        flow.moveBack()
      }
      .tint(Color(uiColor: .label))
      .frame(minWidth: 44, minHeight: 44)
      .contentShape(Rectangle())
      .accessibilityIdentifier("carebrief.onboarding.back")
    }
  }

  private var primaryButton: some View {
    Button(primaryButtonCopy.text(for: language)) {
      if let exit = flow.moveNext() {
        onExit(exit)
      }
    }
    .buttonStyle(.borderedProminent)
    .tint(Color(uiColor: .label))
    .foregroundStyle(Color(uiColor: .systemBackground))
    .frame(minWidth: 44, minHeight: 44)
    .contentShape(Rectangle())
    .accessibilityIdentifier(
      flow.isLastPage ? "carebrief.onboarding.start" : "carebrief.onboarding.next"
    )
  }

  private var primaryButtonCopy: BilingualCopy {
    flow.isLastPage ? CareBriefOnboardingCopy.start : CareBriefOnboardingCopy.next
  }
}

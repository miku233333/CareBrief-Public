import SwiftUI

@MainActor
final class CareBriefRootSession: ObservableObject {
  let viewModel: CareBriefViewModel
  @Published var isReplayingOnboarding = false

  init(viewModel: CareBriefViewModel) {
    self.viewModel = viewModel
  }

  func beginOnboardingReplay() {
    isReplayingOnboarding = true
  }

  func finishOnboardingReplay() {
    isReplayingOnboarding = false
  }
}

@MainActor
struct CareBriefRootView: View {
  @AppStorage(CareBriefReadability.storageKey) private var easyReadMode =
    CareBriefReadability.defaultIsEasyReadEnabled
  @AppStorage(CareBriefOnboardingPreferences.storageKey) private var onboardingCompleted =
    CareBriefOnboardingPreferences.defaultIsCompleted
  @AppStorage(CareBriefLanguagePreference.storageKey) private var languagePreference =
    CareBriefLanguagePreference.defaultPreference

  @StateObject private var session: CareBriefRootSession

  init(viewModel: CareBriefViewModel? = nil) {
    _session = StateObject(
      wrappedValue: CareBriefRootSession(viewModel: viewModel ?? CareBriefViewModel())
    )
  }

  var body: some View {
    Group {
      if onboardingCompleted {
        ContentView(
          viewModel: session.viewModel,
          easyReadMode: $easyReadMode,
          languagePreference: $languagePreference,
          onReplayOnboarding: { session.beginOnboardingReplay() }
        )
      } else {
        CareBriefOnboardingView(
          languagePreference: $languagePreference,
          mode: .firstLaunch
        ) { exit in
          onboardingCompleted = CareBriefOnboardingPreferences.completionValue(
            current: onboardingCompleted,
            after: exit
          )
        }
      }
    }
    .environment(\.careBriefAppLanguage, languagePreference.resolvedLanguage)
    .environment(\.locale, languagePreference.resolvedLanguage.locale)
    .onAppear {
      session.viewModel.setAppLanguage(languagePreference.resolvedLanguage)
    }
    .onChange(of: languagePreference.resolvedLanguage) { language in
      session.viewModel.setAppLanguage(language)
    }
    .fullScreenCover(isPresented: $session.isReplayingOnboarding) {
      CareBriefOnboardingView(
        languagePreference: $languagePreference,
        mode: .replay
      ) { _ in
        session.finishOnboardingReplay()
      }
    }
  }
}

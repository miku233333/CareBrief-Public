import SwiftUI

@MainActor
@main
struct CareBriefApp: App {
  #if DEBUG
    private let uiTestViewModel: CareBriefViewModel?

    init() {
      uiTestViewModel = CareBriefUITestSupport.makeViewModelIfRequested()
    }
  #endif

  var body: some Scene {
    WindowGroup {
      #if DEBUG
        CareBriefRootView(viewModel: uiTestViewModel)
      #else
        CareBriefRootView()
      #endif
    }
  }
}

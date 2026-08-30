import SwiftUI

@main
struct PodDockApp: App {
  @State private var environment = AppEnvironment()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(environment)
        .task {
          await environment.bootstrap()
          environment.lock.engageIfNeeded()
        }
    }
    #if os(macOS)
      Settings {
        SettingsView()
          .environment(environment)
      }
    #endif
  }
}

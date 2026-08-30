import SwiftUI

@main
struct PodDockApp: App {
  @State private var environment = AppEnvironment()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(environment)
        .task {
          #if DEBUG
            FileHandle.standardError.write(
              Data("[PodDock] app task start, args=\(ProcessInfo.processInfo.arguments)\n".utf8))
          #endif
          await environment.bootstrap()
          environment.lock.engageIfNeeded()
          #if DEBUG
            FileHandle.standardError.write(
              Data("[PodDock] bootstrap done, accounts=\(environment.accounts.count)\n".utf8))
          #endif
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

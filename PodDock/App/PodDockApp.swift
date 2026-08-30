import SwiftUI

@main
struct PodDockApp: App {
  var body: some Scene {
    WindowGroup {
      RootView()
    }
  }
}

/// M0 骨架占位;M1 起按计划替换为 AddAccountView / DomainListView 等真实界面。
struct RootView: View {
  var body: some View {
    ContentUnavailableView(
      "PodDock",
      systemImage: "dock.rectangle",
      description: Text("工程骨架就绪,界面于 M1/M2 里程碑落地")
    )
  }
}

#Preview("RootView") {
  RootView()
}

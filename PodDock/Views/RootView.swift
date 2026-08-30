import SwiftUI
import DNSPodKit

/// 根路由:锁 → 无账户(添加账户)→ 主界面
struct RootView: View {
  @Environment(AppEnvironment.self) private var environment

  var body: some View {
    Group {
      if environment.lock.isLocked {
        AppLockView()
      } else if environment.accounts.isEmpty {
        AddAccountView()
      } else {
        MainSplitView()
      }
    }
  }
}

/// macOS 侧栏域名 + 详情记录;紧凑态自动退化为 push 导航(iOS 亦可用)
struct MainSplitView: View {
  @Environment(AppEnvironment.self) private var environment
  @State private var selectedDomainID: DomainID?

  var body: some View {
    NavigationSplitView {
      DomainListView(selection: $selectedDomainID)
    } detail: {
      if let domain = environment.domains.domains.first(where: { $0.id == selectedDomainID }) {
        RecordListView(domain: domain)
      } else {
        ContentUnavailableView(
          "Select a Domain",
          systemImage: "globe.desk",
          description: Text("Pick a domain in the sidebar to view and manage its records")
        )
      }
    }
    #if DEBUG
      .task {
        // 调试钩子:--autoselect 自动选中第一个域名(复现"选中即卡死"类问题);
        // 等待 bootstrap 拉完域名列表,避免竞态取到空
        guard ProcessInfo.processInfo.arguments.contains("--autoselect") else { return }
        for _ in 0..<50 {
          if selectedDomainID != nil { return }
          if let first = environment.domains.domains.first {
            FileHandle.standardError.write(Data("[PodDock] autoselect → \(first.name)\n".utf8))
            selectedDomainID = first.id
            return
          }
          try? await Task.sleep(for: .milliseconds(100))
        }
        FileHandle.standardError.write(Data("[PodDock] autoselect timed out waiting for domains\n".utf8))
      }
    #endif
  }
}

#Preview("RootView - mock") {
  let environment = AppEnvironment(accountStore: InMemoryAccountStore(), preferences: PreferencesStore())
  return RootView()
    .environment(environment)
    .task { await environment.bootstrap() }
}

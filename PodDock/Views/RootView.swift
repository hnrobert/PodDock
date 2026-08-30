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
          "选择域名",
          systemImage: "globe.desk",
          description: Text("在侧栏选择一个域名,查看与管理它的解析记录")
        )
      }
    }
  }
}

#Preview("RootView - mock") {
  let environment = AppEnvironment(accountStore: InMemoryAccountStore(), preferences: PreferencesStore())
  return RootView()
    .environment(environment)
    .task { await environment.bootstrap() }
}

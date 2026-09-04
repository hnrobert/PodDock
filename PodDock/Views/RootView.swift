import SwiftUI
import DNSPodKit

/// Root routing: bootstrapping (splash) → lock → no account (add one) → main UI
struct RootView: View {
  @Environment(AppEnvironment.self) private var environment

  var body: some View {
    Group {
      if environment.isBootstrapping {
        VStack(spacing: 12) {
          Image(systemName: "dock.rectangle")
            .font(.system(size: 40))
            .foregroundStyle(.green)
          ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if environment.lock.isLocked {
        AppLockView()
      } else if environment.accounts.isEmpty {
        AddAccountView()
      } else {
        MainSplitView()
      }
    }
  }
}

/// macOS sidebar domains + detail records; collapses to push navigation on iOS
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
        // Debug hook: --autoselect picks the first domain (reproduces select-to-crash issues);
        // Wait for bootstrap to finish loading domains; racing it reads empty
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

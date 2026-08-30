import SwiftUI
import DNSPodKit

/// 设置(macOS Settings scene;iOS 于 M4 挂到导航):账户管理/应用锁/DoH 默认/关于。
struct SettingsView: View {
  @Environment(AppEnvironment.self) private var environment
  @State private var isShowingAdd = false
  @State private var pendingRemove: Account?

  var body: some View {
    Form {
      Section("Accounts") {
        ForEach(environment.accounts) { account in
          HStack {
            Image(
              systemName:
                account.id == environment.preferences.currentAccountID
                ? "checkmark.circle.fill" : "circle"
            )
            .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
              Text(account.label)
              Text("Token ID \(account.loginTokenID) · \(account.apiFlavor == .legacy ? "Legacy API" : "API 3.0")")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if account.id != environment.preferences.currentAccountID {
              Button("Switch") {
                Task { await environment.switchAccount(to: account.id) }
              }
            }
            Button("Remove", role: .destructive) {
              pendingRemove = account
            }
          }
        }
        Button("Add Account…") { isShowingAdd = true }
      }

      Section("Security") {
        Toggle("Face ID / Touch ID App Lock", isOn: Binding(
          get: { environment.preferences.appLockEnabled },
          set: { enabled in
            environment.preferences.appLockEnabled = enabled
            if !enabled { environment.lock.clearLock() }
          }
        ))
        Text("Identity verification is required at cold start; credentials stay encrypted in the local Keychain and never sync.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Propagation") {
        Picker("Default DoH Provider", selection: Binding(
          get: { environment.preferences.preferredDoHProvider },
          set: { environment.preferences.preferredDoHProvider = $0 }
        )) {
          ForEach(DoHProvider.allCases) { provider in
            Text(provider.displayName).tag(provider)
          }
        }
        Text("Falls back to the system resolver when DoH is unreachable; results are labeled by source.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("About") {
        LabeledContent("Version", value: "0.1.0")
        LabeledContent("Local MCP Service", value: "Coming in M3")
        Link("DNSPod Console", destination: URL(string: "https://console.dnspod.cn")!)
      }

      if let message = environment.latestMessage {
        Section { Text(message).foregroundStyle(.secondary) }
      }
    }
    .formStyle(.grouped)
    .frame(minWidth: 480, minHeight: 420)
    .sheet(isPresented: $isShowingAdd) {
      AddAccountSheetEmbedded()
    }
    .confirmationDialog(
      "Remove Account",
      isPresented: Binding(
        get: { pendingRemove != nil },
        set: { if !$0 { pendingRemove = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("Remove \(pendingRemove?.label ?? "")", role: .destructive) {
        if let account = pendingRemove {
          Task { await environment.removeAccount(account.id) }
        }
        pendingRemove = nil
      }
    } message: {
      Text("Only removes local credentials; your DNSPod account is untouched.")
    }
  }
}

/// 设置内嵌的添加账户(复用 AddAccountView,成功后留在设置页)
private struct AddAccountSheetEmbedded: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    AddAccountView()
      .frame(minWidth: 560, minHeight: 560)
  }
}

import SwiftUI
import DNSPodKit

/// 设置(macOS Settings scene;iOS 于 M4 挂到导航):账户管理/应用锁/DoH 默认/关于。
struct SettingsView: View {
  @Environment(AppEnvironment.self) private var environment
  @State private var isShowingAdd = false
  @State private var pendingRemove: Account?

  var body: some View {
    Form {
      Section("账户") {
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
              Text("Token ID \(account.loginTokenID) · \(account.apiFlavor == .legacy ? "传统 API" : "API 3.0")")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if account.id != environment.preferences.currentAccountID {
              Button("切换") {
                Task { await environment.switchAccount(to: account.id) }
              }
            }
            Button("删除", role: .destructive) {
              pendingRemove = account
            }
          }
        }
        Button("添加账户…") { isShowingAdd = true }
      }

      Section("安全") {
        Toggle("Face ID / Touch ID 应用锁", isOn: Binding(
          get: { environment.preferences.appLockEnabled },
          set: { enabled in
            environment.preferences.appLockEnabled = enabled
            if !enabled { environment.lock.clearLock() }
          }
        ))
        Text("开启后冷启动需验证身份;凭据本身始终加密存于本机 Keychain(不随设备迁移)。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("解析检测") {
        Picker("默认 DoH 服务商", selection: Binding(
          get: { environment.preferences.preferredDoHProvider },
          set: { environment.preferences.preferredDoHProvider = $0 }
        )) {
          ForEach(DoHProvider.allCases) { provider in
            Text(provider.displayName).tag(provider)
          }
        }
        Text("DoH 不可达时自动回退系统解析,结果会标注来源。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("关于") {
        LabeledContent("版本", value: "0.1.0")
        LabeledContent("本地 MCP 服务", value: "M3 里程碑提供")
        Link("DNSPod 控制台", destination: URL(string: "https://console.dnspod.cn")!)
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
      "删除账户",
      isPresented: Binding(
        get: { pendingRemove != nil },
        set: { if !$0 { pendingRemove = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("删除 \(pendingRemove?.label ?? "")", role: .destructive) {
        if let account = pendingRemove {
          Task { await environment.removeAccount(account.id) }
        }
        pendingRemove = nil
      }
    } message: {
      Text("仅从本机移除凭据,不影响 DNSPod 账号本身。")
    }
  }
}

/// 设置内嵌的添加账户(复用 AddAccountView 的核心表单,成功后留在设置页)
private struct AddAccountSheetEmbedded: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    AddAccountView()
      .frame(minWidth: 560, minHeight: 560)
  }
}

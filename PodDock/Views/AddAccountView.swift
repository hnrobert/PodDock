import SwiftUI
import DNSPodKit

/// 添加账户:粘贴 "ID,Token" 自动拆分 + 控制台引导链接;凭据验证通过才落 Keychain。
struct AddAccountView: View {
  @Environment(AppEnvironment.self) private var environment

  @State private var tokenID = ""
  @State private var tokenKey = ""
  @State private var label = ""
  @State private var isWorking = false
  @State private var errorMessage: String?

  private let consoleURL = URL(string: "https://console.dnspod.cn/account/token/token")!

  var body: some View {
    VStack(spacing: 24) {
      Image(systemName: "dock.rectangle.fill")
        .font(.system(size: 56))
        .foregroundStyle(.green)

      Text("添加 DNSPod 账户").font(.title2.bold())
      Text("使用 DNSPod API Token 连接你的账户。Token 只保存在本机 Keychain。")
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      Form {
        Section("DNSPod API Token") {
          LabeledContent("Token ID") {
            TextField("Token ID", text: $tokenID, prompt: Text("例如 123456"))
          }
          LabeledContent("Token Key") {
            SecureField("Token Key", text: $tokenKey, prompt: Text("密钥"))
          }
          LabeledContent("标签(可选)") {
            TextField("标签", text: $label, prompt: Text("显示名称,默认取 ID 后 4 位"))
          }
        }

        Section {
          Link("打开 DNSPod 控制台创建 API Token", destination: consoleURL)
          Text("控制台 → 账户 → API 密钥。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .formStyle(.grouped)
      .frame(maxWidth: 520)

      if let errorMessage {
        Text(errorMessage).foregroundStyle(.red).font(.callout)
      }

      Button {
        Task { await submit() }
      } label: {
        if isWorking {
          ProgressView().controlSize(.small)
        } else {
          Text("验证并添加").frame(minWidth: 120)
        }
      }
      .buttonStyle(.borderedProminent)
      .disabled(tokenID.isEmpty || tokenKey.isEmpty || isWorking)
    }
    .padding(32)
    .frame(minWidth: 560, minHeight: 640)
  }

  private func submit() async {
    isWorking = true
    errorMessage = nil
    defer { isWorking = false }
    do {
      try await environment.addAccount(
        tokenID: tokenID.trimmingCharacters(in: .whitespaces),
        tokenKey: tokenKey.trimmingCharacters(in: .whitespaces),
        label: label.isEmpty ? nil : label)
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

#Preview("AddAccountView") {
  AddAccountView()
    .environment(AppEnvironment(accountStore: InMemoryAccountStore(), preferences: PreferencesStore()))
}

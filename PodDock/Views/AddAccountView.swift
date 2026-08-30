import SwiftUI
import DNSPodKit

/// 添加账户:粘贴 "ID,Token" 自动拆分 + 控制台引导链接;凭据验证通过才落 Keychain。
struct AddAccountView: View {
  @Environment(AppEnvironment.self) private var environment

  @State private var pasted = ""
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
        Section("一键粘贴") {
          TextField("粘贴 Token(格式:ID,Token)", text: $pasted)
            .onSubmit(applyPaste)
          if !pasted.isEmpty {
            Button("解析并填入", action: applyPaste)
          }
        }

        Section("或手动填写") {
          LabeledContent("Token ID") {
            TextField("例如 123456", text: $tokenID)
          }
          LabeledContent("Token Key") {
            SecureField("密钥", text: $tokenKey)
          }
          LabeledContent("标签(可选)") {
            TextField("显示名称,默认取 ID 后 4 位", text: $label)
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
    .frame(minWidth: 560, minHeight: 560)
  }

  private func applyPaste() {
    guard let parsed = Account.parse(pasted: pasted) else {
      errorMessage = "粘贴内容无法解析,需要 \"ID,Token\" 格式"
      return
    }
    tokenID = parsed.id
    tokenKey = parsed.token
    errorMessage = nil
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

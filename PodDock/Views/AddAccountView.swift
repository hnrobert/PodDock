import SwiftUI
import DNSPodKit

/// Add account: credentials verified before storage.
struct AddAccountView: View {
  @Environment(AppEnvironment.self) private var environment

  @State private var tokenID = ""
  @State private var tokenKey = ""
  @State private var label = ""
  @State private var isWorking = false
  @State private var errorMessage: String?

  private let consoleURL = URL(string: "https://console.dnspod.cn/account/token/token")!

  var body: some View {
    VStack(spacing: 0) {
      // Compact header
      VStack(spacing: 8) {
        Image(systemName: "dock.rectangle")
          .font(.system(size: 36))
          .foregroundStyle(.green)
        Text("Add DNSPod Account").font(.title3.bold())
        Text("Connect with a DNSPod API Token. It is stored only on this Mac.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .padding(.top, 20)
      .padding(.bottom, 12)

      Form {
        Section("DNSPod API Token") {
          LabeledContent("Token ID") {
            TextField("", text: $tokenID, prompt: Text("e.g. 123456"))
          }
          LabeledContent("Token Key") {
            SecureField("", text: $tokenKey, prompt: Text("secret"))
          }
          LabeledContent("Label (optional)") {
            TextField("", text: $label, prompt: Text("Display name; defaults to last 4 digits of the ID"))
          }
        }

        Section {
          Link("Open the DNSPod console to create an API Token", destination: consoleURL)
          Text("Console → Account → API Keys.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .formStyle(.grouped)

      // Error + button pinned to the bottom
      VStack(spacing: 10) {
        if let errorMessage {
          Text(errorMessage)
            .foregroundStyle(.red)
            .font(.caption)
            .lineLimit(2)
        }
        Button {
          Task { await submit() }
        } label: {
          if isWorking {
            ProgressView().controlSize(.small)
          } else {
            Text("Verify & Add").frame(minWidth: 120)
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(tokenID.isEmpty || tokenKey.isEmpty || isWorking)
      }
      .padding(.top, 10)
      .padding(.bottom, 16)
    }
    .frame(minWidth: 480, idealWidth: 520, maxWidth: 560)
    .fixedSize(horizontal: false, vertical: true)
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
      errorMessage = describeError(error)
    }
  }
}

#Preview("AddAccountView") {
  AddAccountView()
    .environment(AppEnvironment(accountStore: InMemoryAccountStore(), preferences: PreferencesStore()))
}

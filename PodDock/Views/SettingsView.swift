import SwiftUI
#if canImport(AppKit)
  import AppKit
#endif
import DNSPodKit

/// Settings (macOS Settings scene; iOS lands in M4): accounts/app lock/DoH default/about.
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

      Section("AI Assistant") {
        Picker("Provider", selection: Binding(
          get: { environment.preferences.llmProvider },
          set: { environment.preferences.llmProvider = $0 }
        )) {
          ForEach(LLMProviderKind.allCases) { kind in
            Text(kind.displayName).tag(kind)
          }
        }
        LabeledContent("Model") {
          TextField("", text: Binding(
            get: { environment.preferences.llmModel },
            set: { environment.preferences.llmModel = $0 }
          ), prompt: Text(LLMKeyField.placeholderModel(for: environment.preferences.llmProvider)))
        }
        if environment.preferences.llmProvider == .openAICompatible {
          LabeledContent("Base URL") {
            TextField("", text: Binding(
              get: { environment.preferences.llmBaseURL },
              set: { environment.preferences.llmBaseURL = $0 }
            ), prompt: Text("https://api.openai.com/v1"))
          }
        }
        LLMKeyField(kind: environment.preferences.llmProvider)
        Text("The key is stored only in this Mac's Keychain. Write operations always require your confirmation.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Local MCP Service") {
        Toggle("Run MCP server on this Mac", isOn: Binding(
          get: { environment.mcpHost.isRunning },
          set: { enabled in
            Task { enabled ? await environment.mcpHost.start() : await environment.mcpHost.stop() }
          }
        ))
        if environment.mcpHost.isRunning {
          LabeledContent("Endpoint", value: environment.mcpHost.endpointURL)
          HStack {
            Text(environment.mcpHost.connectCommand)
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
              .lineLimit(2)
              .truncationMode(.middle)
            Spacer()
            Button("Copy") {
              #if canImport(AppKit)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(environment.mcpHost.connectCommand, forType: .string)
              #endif
            }
          }
          Text("External AI clients operate the same account as this app. The bearer token is endpoint protection, independent of DNSPod credentials.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if let error = environment.mcpHost.errorMessage {
          Text(error).foregroundStyle(.red).font(.caption)
        }
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

/// Add-account embedded in settings (reuses AddAccountView; stays on success)
private struct AddAccountSheetEmbedded: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    AddAccountView()
      .frame(minWidth: 560, minHeight: 560)
  }
}

/// LLM API key row (Keychain-backed)
private struct LLMKeyField: View {
  let kind: LLMProviderKind
  @State private var key = ""
  @State private var isSaved = false
  private let store = SecretStore()

  static func placeholderModel(for kind: LLMProviderKind) -> String {
    switch kind {
    case .anthropic: AnthropicClient.defaultModel
    case .openAICompatible: OpenAICompatClient.defaultModel
    }
  }

  var body: some View {
    LabeledContent("API Key") {
      HStack {
        SecureField("", text: $key, prompt: Text(isSaved ? "•••• (saved)" : "sk-…"))
          .onChange(of: key) { _, newValue in
            if !newValue.isEmpty {
              store.write(newValue.trimmingCharacters(in: .whitespaces))
              isSaved = true
            }
          }
        if isSaved {
          Button("Remove") {
            store.delete()
            key = ""
            isSaved = false
          }
        }
      }
    }
    .onAppear {
      isSaved = store.read() != nil
    }
  }
}

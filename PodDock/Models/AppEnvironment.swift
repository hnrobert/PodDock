import Foundation
import DNSPodKit
import Observation

/// App root model: account wiring/switching, client factory, lock, --uitest-mock hook.
@MainActor
@Observable
final class AppEnvironment {
  let accountStore: AccountStoring
  let preferences: PreferencesStore
  let lock: AppLockController
  let domains: DomainListModel
  let assistant: AssistantModel
  let mcpHost: MCPHostService
  let isMockMode: Bool

  private(set) var accounts: [Account] = []
  private(set) var client: DNSPodClient?

  /// Non-blocking feedback for current-account operations (errors / partial success)
  var latestMessage: String?

  init(accountStore: AccountStoring? = nil, preferences: PreferencesStore? = nil) {
    let isMock: Bool
    #if DEBUG
      isMock = ProcessInfo.processInfo.arguments.contains("--uitest-mock")
    #else
      isMock = false
    #endif
    isMockMode = isMock

    let prefs = preferences ?? PreferencesStore()
    self.preferences = prefs
    lock = AppLockController(preferences: prefs)
    assistant = AssistantModel()
    mcpHost = MCPHostService()

    #if DEBUG
      if isMock {
        FileHandle.standardError.write(Data("[PodDock] mock mode ON\n".utf8))
        let store = InMemoryAccountStore()
        let seed = Account(loginTokenID: "123456", loginToken: "mock-token")
        self.accountStore = store
        accounts = [seed]
        client = MockDNSPodClient()
        prefs.currentAccountID = seed.id
        domains = DomainListModel()
        domains.attach(environment: self)
        return
      }
    #endif

    #if os(macOS)
      // macOS: file store — the keychain scopes items by code-signing identity,
      // which changes every Xcode rebuild and loses accounts between debug sessions
      self.accountStore = accountStore ?? FileAccountStore()
    #else
      self.accountStore = accountStore ?? KeychainAccountStore()
    #endif
    domains = DomainListModel()
    domains.attach(environment: self)
  }

  /// Bootstrap: load accounts → restore the current one → fetch domains
  func bootstrap() async {
    domains.attach(environment: self)
    assistant.attach(environment: self)
    mcpHost.attach(environment: self)
    if isMockMode {
      // Mock mode: client injected in init (activate would overwrite it with a real one)
      await domains.load()
      return
    }
    accounts = (try? await accountStore.accounts()) ?? []
    let target =
      accounts.first { $0.id == preferences.currentAccountID } ?? accounts.first
    if let target {
      activate(target)
      await domains.load()
    }
  }

  var currentAccount: Account? {
    accounts.first { $0.id == preferences.currentAccountID }
  }

  /// Client factory: builds the matching impl for the account's API flavor;
  /// `lang` follows the system language so DNSPod server errors come back in it too
  static func makeClient(for account: Account) -> DNSPodClient {
    switch account.apiFlavor {
    case .legacy:
      LegacyClient(
        tokenID: account.loginTokenID, tokenKey: account.loginToken,
        lang: preferredAPILanguage)
    case .tencentCloud:
      TencentCloudClient()
    }
  }

  static var preferredAPILanguage: String {
    Locale.current.language.languageCode?.identifier.hasPrefix("zh") == true ? "cn" : "en"
  }

  /// Add account: validate credentials with a throwaway client (Domain.List doubles for this) before touching Keychain
  func addAccount(tokenID: String, tokenKey: String, label: String?) async throws {
    let account = Account(label: label, loginTokenID: tokenID, loginToken: tokenKey)
    let candidate = Self.makeClient(for: account)
    do {
      try await candidate.validateCredentials()
    } catch let error as DNSPodError where error.isAuthenticationFailure {
      throw error
    }
    try await accountStore.save(account)
    accounts.append(account)
    activate(account)
    await domains.load()
  }

  func switchAccount(to id: UUID) async {
    guard let account = accounts.first(where: { $0.id == id }) else { return }
    activate(account)
    await domains.load()
  }

  func removeAccount(_ id: UUID) async {
    try? await accountStore.remove(id: id)
    accounts.removeAll { $0.id == id }
    if preferences.currentAccountID == id {
      preferences.currentAccountID = nil
      client = nil
      if let next = accounts.first {
        activate(next)
        await domains.load()
      }
    }
  }

  private func activate(_ account: Account) {
    preferences.currentAccountID = account.id
    client = Self.makeClient(for: account)
  }

  /// On auth failure: drop the stale credentials and prompt to re-add
  func handleAuthenticationFailure() async {
    guard let current = currentAccount else { return }
    latestMessage = String(
      localized: "Credentials for \(current.label) are no longer valid; please re-add the account.")
    await removeAccount(current.id)
  }
}

import Foundation
import DNSPodKit
import Observation

/// App 根模型:账户装配/切换、client 工厂、锁、--uitest-mock 钩子。
@MainActor
@Observable
final class AppEnvironment {
  let accountStore: AccountStoring
  let preferences: PreferencesStore
  let lock: AppLockController
  let domains: DomainListModel
  let isMockMode: Bool

  private(set) var accounts: [Account] = []
  private(set) var client: DNSPodClient?

  /// 当前账户操作反馈(非阻塞错误/部分成功提示)
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

    #if DEBUG
      if isMock {
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

    self.accountStore = accountStore ?? KeychainAccountStore()
    domains = DomainListModel()
    domains.attach(environment: self)
  }

  /// 启动装配:读账户 → 恢复当前账户 → 拉域名
  func bootstrap() async {
    if !isMockMode {
      accounts = (try? await accountStore.accounts()) ?? []
    }
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

  /// client 工厂:按账户的 API 风味装配对应实现
  static func makeClient(for account: Account) -> DNSPodClient {
    switch account.apiFlavor {
    case .legacy:
      LegacyClient(tokenID: account.loginTokenID, tokenKey: account.loginToken)
    case .tencentCloud:
      TencentCloudClient()
    }
  }

  /// 添加账户:先用临时 client 验证凭据(Domain.List 兼任),通过才落 Keychain
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

  /// 认证失败时踢回:移除失效凭据并提示重新添加
  func handleAuthenticationFailure() async {
    guard let current = currentAccount else { return }
    latestMessage = String(
      localized: "Credentials for \(current.label) are no longer valid; please re-add the account.")
    await removeAccount(current.id)
  }
}

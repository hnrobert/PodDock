import Foundation

/// 账户的 API 风味——决定用哪个 DNSPodClient 实现。
public enum APIFlavor: String, Sendable, Codable, CaseIterable {
  case legacy
  case tencentCloud
}

/// 一套 DNSPod 凭据。label 为本地手填(传统 API 无账户资料接口),
/// 默认 `账户 <ID 后 4 位>`。
public struct Account: Identifiable, Hashable, Sendable, Codable {
  public let id: UUID
  public var label: String
  public var apiFlavor: APIFlavor
  public var loginTokenID: String
  public var loginToken: String
  public let createdAt: Date

  public init(
    id: UUID = UUID(),
    label: String? = nil,
    apiFlavor: APIFlavor = .legacy,
    loginTokenID: String,
    loginToken: String,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.label = label ?? Account.defaultLabel(tokenID: loginTokenID)
    self.apiFlavor = apiFlavor
    self.loginTokenID = loginTokenID
    self.loginToken = loginToken
    self.createdAt = createdAt
  }

  public static func defaultLabel(tokenID: String) -> String {
    let suffix = String(tokenID.suffix(4))
    return "账户 \(suffix)"
  }

  /// "ID,Token" 粘贴拆分(登录辅助:整串粘贴自动填两栏)
  public static func parse(pasted: String) -> (id: String, token: String)? {
    let parts = pasted
      .split(separator: ",", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
    return (parts[0], parts[1])
  }
}

/// 账户存取协议。Keychain 实现在 App target(Security 框架 Apple 专用,Kit 保持 Linux 纯净);
/// 测试 / XCUITest / 未来 CLI 用 InMemoryAccountStore(CLI 用环境变量装配)。
public protocol AccountStoring: Sendable {
  func save(_ account: Account) async throws
  func account(id: UUID) async throws -> Account?
  func accounts() async throws -> [Account]
  func remove(id: UUID) async throws
}

/// 内存实现:测试、XCUITest(--uitest-mock 模式)、SwiftUI Preview。
public actor InMemoryAccountStore: AccountStoring {
  private var storage: [UUID: Account] = [:]

  public init() {}

  public func save(_ account: Account) {
    storage[account.id] = account
  }

  public func account(id: UUID) -> Account? {
    storage[id]
  }

  public func accounts() -> [Account] {
    storage.values.sorted { $0.createdAt < $1.createdAt }
  }

  public func remove(id: UUID) {
    storage[id] = nil
  }
}

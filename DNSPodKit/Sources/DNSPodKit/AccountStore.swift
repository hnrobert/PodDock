import Foundation

/// Account API flavor — picks the DNSPodClient impl.
public enum APIFlavor: String, Sendable, Codable, CaseIterable {
  case legacy
  case tencentCloud
}

/// One DNSPod credential set. The label is local (the legacy API has no profile endpoint),
/// Defaults to `Account <last 4 of the ID>`.
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

  /// Parses a pasted "ID,Token" (login helper: one paste fills both fields)
  public static func parse(pasted: String) -> (id: String, token: String)? {
    let parts = pasted
      .split(separator: ",", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
    return (parts[0], parts[1])
  }
}

/// Account storage protocol. The Keychain impl lives in the App target (Security is Apple-only; the Kit stays Linux-clean);
/// Tests/XCUITests/the future CLI use InMemoryAccountStore (the CLI wires it from env vars).
public protocol AccountStoring: Sendable {
  func save(_ account: Account) async throws
  func account(id: UUID) async throws -> Account?
  func accounts() async throws -> [Account]
  func remove(id: UUID) async throws
}

/// In-memory impl: tests, XCUITests (--uitest-mock), SwiftUI previews.
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

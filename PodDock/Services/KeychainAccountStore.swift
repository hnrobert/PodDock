import Foundation
import Security
import DNSPodKit

/// Keychain account store (the Security framework is Apple-only, hence App target, not Kit).
///
/// One generic password per account: account = UUID (not the Token ID, so labels can change),
/// value = Account JSON.
///
/// macOS: always the file (login) keychain — `kSecUseDataProtectionKeychain` on sandboxed
/// macOS with dev-team signing scopes items into an access group derived from the signing
/// identity, which changes between builds and loses items. The file keychain has no such
/// dependency and persists reliably across debug/release/ad-hoc launches.
/// iOS: always DataProtection (the flag is macOS-only anyway).
final class KeychainError: LocalizedError {
  let status: OSStatus
  init(status: OSStatus) { self.status = status }
  var errorDescription: String? {
    String(localized: "Keychain operation failed (OSStatus \(Int(status)))")
  }
}

final class KeychainAccountStore: AccountStoring, Sendable {
  let service: String

  init(service: String = "com.robert.poddock.account") {
    self.service = service
  }

  // MARK: - Query building

  #if os(macOS)
    private static let useDataProtection = false
  #else
    private static let useDataProtection = true
  #endif

  private func baseQuery(id: UUID? = nil) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
    ]
    if Self.useDataProtection {
      query[kSecUseDataProtectionKeychain as String] = true
    }
    if let id {
      query[kSecAttrAccount as String] = id.uuidString
    }
    return query
  }

  // MARK: - Sync implementation

  private func saveSync(_ account: Account) throws {
    let data = try JSONEncoder().encode(account)
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]

    var addQuery = baseQuery(id: account.id)
    for (key, value) in attributes {
      addQuery[key] = value
    }
    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    if addStatus == errSecDuplicateItem {
      let updateStatus = SecItemUpdate(
        baseQuery(id: account.id) as CFDictionary,
        attributes as CFDictionary)
      guard updateStatus == errSecSuccess else { throw KeychainError(status: updateStatus) }
    } else if addStatus != errSecSuccess {
      throw KeychainError(status: addStatus)
    }
  }

  private func accountSync(id: UUID) -> Account? {
    var query = baseQuery(id: id)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess,
      let dict = item as? [String: Any],
      let data = dict[kSecValueData as String] as? Data
    else { return nil }
    return try? JSONDecoder().decode(Account.self, from: data)
  }

  private func accountsSync() -> [Account] {
    var query = baseQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitAll
    var items: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &items)
    guard status == errSecSuccess,
      let array = items as? [[String: Any]]
    else { return [] }
    return array.compactMap { dict in
      guard let data = dict[kSecValueData as String] as? Data else { return nil }
      return try? JSONDecoder().decode(Account.self, from: data)
    }
    .sorted { $0.createdAt < $1.createdAt }
  }

  private func removeSync(id: UUID) throws {
    let status = SecItemDelete(baseQuery(id: id) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError(status: status)
    }
  }

  // MARK: - AccountStoring (protocol is async; bridges the sync impl)

  func save(_ account: Account) async throws { try saveSync(account) }
  func account(id: UUID) async throws -> Account? { accountSync(id: id) }
  func accounts() async throws -> [Account] { accountsSync() }
  func remove(id: UUID) async throws { try removeSync(id: id) }
}

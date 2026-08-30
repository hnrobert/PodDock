import Foundation
import Security
import DNSPodKit

/// Keychain 账户存储(Security 框架 Apple 专用,故在 App target 而非 Kit)。
///
/// 每账户一条 generic password:account = UUID(不用 Token ID 当 key,便于换标签),
/// value = Account JSON。`kSecUseDataProtectionKeychain = true` 是 macOS 上最容易
/// 踩的坑——不设则走文件钥匙串,`kSecAttrAccessible` 被忽略,与 iOS 行为分叉。
struct KeychainError: LocalizedError {
  let status: OSStatus
  var errorDescription: String? { "Keychain 操作失败(OSStatus \(status))" }
}

struct KeychainAccountStore: AccountStoring {
  let service: String

  init(service: String = "com.robert.poddock.account") {
    self.service = service
  }

  private func baseQuery(id: UUID? = nil) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecUseDataProtectionKeychain as String: true,
    ]
    if let id {
      query[kSecAttrAccount as String] = id.uuidString
    }
    return query
  }

  // MARK: - 同步实现(SecItem 操作微小,无阻塞风险)

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
        baseQuery(id: account.id) as CFDictionary, attributes as CFDictionary)
      guard updateStatus == errSecSuccess else { throw KeychainError(status: updateStatus) }
    } else if addStatus != errSecSuccess {
      throw KeychainError(status: addStatus)
    }
  }

  private func accountSync(id: UUID) -> Account? {
    var query = baseQuery(id: id)
    query[kSecReturnAttributes as String] = true
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let dict = item as? [String: Any],
      let data = dict[kSecValueData as String] as? Data
    else { return nil }
    return try? JSONDecoder().decode(Account.self, from: data)
  }

  private func accountsSync() -> [Account] {
    var query = baseQuery()
    query[kSecReturnAttributes as String] = true
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitAll

    var items: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &items)
    guard status == errSecSuccess, let array = items as? [[String: Any]] else { return [] }
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

  // MARK: - AccountStoring(协议是 async,桥接同步实现)

  func save(_ account: Account) async throws { try saveSync(account) }
  func account(id: UUID) async throws -> Account? { accountSync(id: id) }
  func accounts() async throws -> [Account] { accountsSync() }
  func remove(id: UUID) async throws { try removeSync(id: id) }
}

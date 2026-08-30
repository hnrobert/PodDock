import Foundation
import Security
import DNSPodKit

/// Keychain 账户存储(Security 框架 Apple 专用,故在 App target 而非 Kit)。
///
/// 每账户一条 generic password:account = UUID(不用 Token ID 当 key,便于换标签),
/// value = Account JSON。优先走 Data Protection Keychain(`kSecUseDataProtectionKeychain
/// = true`,与 iOS 一致);但当进程缺少 entitlement 上下文时(macOS -34018
/// errSecMissingEntitlement——典型:从调试器直接启动裸二进制、无开发团队的临时签名),
/// 自动降级到文件钥匙串并记住该模式,避免开发环境完全不可用。
final class KeychainError: LocalizedError {
  let status: OSStatus
  init(status: OSStatus) { self.status = status }
  var errorDescription: String? {
    String(localized: "Keychain operation failed (OSStatus \(Int(status)))")
  }
}

final class KeychainAccountStore: AccountStoring, @unchecked Sendable {
  let service: String
  private let lock = NSLock()
  /// 已探测到无 entitlement 上下文时置 false,后续直接走文件钥匙串
  private var useDataProtection = true

  init(service: String = "com.robert.poddock.account") {
    self.service = service
  }

  private func baseQuery(id: UUID? = nil, dataProtection: Bool) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
    ]
    if dataProtection {
      query[kSecUseDataProtectionKeychain as String] = true
    }
    if let id {
      query[kSecAttrAccount as String] = id.uuidString
    }
    return query
  }

  /// 带 -34018 降级重试的 SecItem 执行器
  private func perform(_ operation: (Bool) -> OSStatus) throws {
    lock.lock()
    let preferDataProtection = useDataProtection
    lock.unlock()

    var status = operation(preferDataProtection)
    if status == errSecMissingEntitlement, preferDataProtection {
      // 无 entitlement 上下文(调试器直启/临时签名):降级文件钥匙串并记住
      lock.lock()
      useDataProtection = false
      lock.unlock()
      status = operation(false)
    }
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError(status: status)
    }
  }

  // MARK: - 同步实现(SecItem 操作微小,无阻塞风险)

  private func saveSync(_ account: Account) throws {
    let data = try JSONEncoder().encode(account)

    try perform { dataProtection in
      let attributes: [String: Any] = [
        kSecValueData as String: data,
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      ]
      var addQuery = baseQuery(id: account.id, dataProtection: dataProtection)
      for (key, value) in attributes {
        addQuery[key] = value
      }
      let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
      if addStatus == errSecDuplicateItem {
        return SecItemUpdate(
          baseQuery(id: account.id, dataProtection: dataProtection) as CFDictionary,
          attributes as CFDictionary)
      }
      return addStatus
    }
  }

  private func accountSync(id: UUID) -> Account? {
    var result: Account?
    try? perform { dataProtection in
      var query = baseQuery(id: id, dataProtection: dataProtection)
      query[kSecReturnAttributes as String] = true
      query[kSecReturnData as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitOne

      var item: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &item)
      guard status == errSecSuccess, let dict = item as? [String: Any],
        let data = dict[kSecValueData as String] as? Data
      else { return status }
      result = try? JSONDecoder().decode(Account.self, from: data)
      return errSecSuccess
    }
    return result
  }

  private func accountsSync() -> [Account] {
    var accounts: [Account] = []
    try? perform { dataProtection in
      var query = baseQuery(dataProtection: dataProtection)
      query[kSecReturnAttributes as String] = true
      query[kSecReturnData as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitAll

      var items: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &items)
      guard status == errSecSuccess, let array = items as? [[String: Any]] else { return status }
      accounts = array.compactMap { dict in
        guard let data = dict[kSecValueData as String] as? Data else { return nil }
        return try? JSONDecoder().decode(Account.self, from: data)
      }
      .sorted { $0.createdAt < $1.createdAt }
      return errSecSuccess
    }
    return accounts
  }

  private func removeSync(id: UUID) throws {
    try perform { dataProtection in
      SecItemDelete(baseQuery(id: id, dataProtection: dataProtection) as CFDictionary)
    }
  }

  // MARK: - AccountStoring(协议是 async,桥接同步实现)

  func save(_ account: Account) async throws { try saveSync(account) }
  func account(id: UUID) async throws -> Account? { accountSync(id: id) }
  func accounts() async throws -> [Account] { accountsSync() }
  func remove(id: UUID) async throws { try removeSync(id: id) }
}

import Foundation
import Security
import DNSPodKit

/// Keychain account store (the Security framework is Apple-only, hence App target, not Kit).
///
/// One generic password per account: account = UUID (not the Token ID, so labels can change),
/// value = Account JSON. Prefers the Data Protection Keychain (`kSecUseDataProtectionKeychain
/// = true`, matching iOS); but when the process lacks entitlement context (macOS -34018
/// errSecMissingEntitlement — typical: a bare binary launched from a debugger, ad-hoc signing with no team),
/// Falls back to the file keychain and remembers the mode, keeping dev environments usable.
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
  /// Set false once an entitlement context is found missing; later calls go straight to the file keychain
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

  /// Run in a specific keychain mode; on -34018 (missing entitlement) flag the global fallback
  private func performIn(_ dataProtection: Bool, _ operation: (Bool) -> OSStatus) -> OSStatus {
    let status = operation(dataProtection)
    if status == errSecMissingEntitlement && dataProtection {
      lock.lock()
      useDataProtection = false
      lock.unlock()
    }
    return status
  }

  /// Write path: run in the preferred mode, auto-retry on -34018
  private func perform(_ operation: (Bool) -> OSStatus) throws {
    lock.lock()
    let preferDataProtection = useDataProtection
    lock.unlock()

    var status = performIn(preferDataProtection, operation)
    if status == errSecMissingEntitlement, preferDataProtection {
      status = performIn(false, operation)
    }
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError(status: status)
    }
  }

  // MARK: - Sync implementation (SecItem ops are tiny, no blocking risk)

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
    // Read both modes: an account may live in either keychain (e.g. a debug session wrote the file keychain)
    for dataProtection in [true, false] {
      var result: Account?
      _ = performIn(dataProtection) { dp in
        var query = baseQuery(id: id, dataProtection: dp)
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
      if result != nil { return result }
    }
    return nil
  }

  private func accountsSync() -> [Account] {
    // Read both modes and merge by UUID (an account may exist on only one side)
    var merged: [UUID: Account] = [:]
    for dataProtection in [true, false] {
      _ = performIn(dataProtection) { dp in
        var query = baseQuery(dataProtection: dp)
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll

        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        guard status == errSecSuccess, let array = items as? [[String: Any]] else { return status }
        for dict in array {
          guard let data = dict[kSecValueData as String] as? Data,
            let account = try? JSONDecoder().decode(Account.self, from: data)
          else { continue }
          merged[account.id] = account
        }
        return errSecSuccess
      }
    }
    return merged.values.sorted { $0.createdAt < $1.createdAt }
  }

  private func removeSync(id: UUID) throws {
    try perform { dataProtection in
      SecItemDelete(baseQuery(id: id, dataProtection: dataProtection) as CFDictionary)
    }
  }

  // MARK: - AccountStoring (protocol is async; bridges the sync impl)

  func save(_ account: Account) async throws { try saveSync(account) }
  func account(id: UUID) async throws -> Account? { accountSync(id: id) }
  func accounts() async throws -> [Account] { accountsSync() }
  func remove(id: UUID) async throws { try removeSync(id: id) }
}

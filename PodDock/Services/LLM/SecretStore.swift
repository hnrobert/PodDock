import Foundation
import Security

/// 单密钥 Keychain 存取(LLM API Key;与账户存储同款双模式 + -34018 降级策略)
struct SecretStore: Sendable {
  let service: String
  let account: String

  init(service: String = "com.robert.poddock.llm", account: String = "api-key") {
    self.service = service
    self.account = account
  }

  private func baseQuery(dataProtection: Bool) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    if dataProtection {
      query[kSecUseDataProtectionKeychain as String] = true
    }
    return query
  }

  func read() -> String? {
    for dataProtection in [true, false] {
      var query = baseQuery(dataProtection: dataProtection)
      query[kSecReturnData as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitOne
      var item: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &item)
      if status == errSecSuccess, let data = item as? Data,
        let string = String(data: data, encoding: .utf8)
      {
        return string
      }
    }
    return nil
  }

  func write(_ secret: String) {
    let data = Data(secret.utf8)
    for dataProtection in [true, false] {
      var addQuery = baseQuery(dataProtection: dataProtection)
      addQuery[kSecValueData as String] = data
      let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
      if addStatus == errSecSuccess { return }
      if addStatus == errSecDuplicateItem {
        let attributes: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(baseQuery(dataProtection: dataProtection) as CFDictionary, attributes as CFDictionary) == errSecSuccess {
          return
        }
      }
    }
  }

  func delete() {
    for dataProtection in [true, false] {
      SecItemDelete(baseQuery(dataProtection: dataProtection) as CFDictionary)
    }
  }
}

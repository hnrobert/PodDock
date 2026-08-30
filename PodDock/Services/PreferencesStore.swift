import Foundation
import DNSPodKit
import Observation

/// 偏好存储(UserDefaults;非机密,凭据只在 Keychain)。
/// 隐私清单已声明 UserDefaults 的 C56D.1 使用理由。
@MainActor
@Observable
final class PreferencesStore {
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let raw = defaults.string(forKey: Self.currentAccountKey), let id = UUID(uuidString: raw) {
      currentAccountID = id
    }
    appLockEnabled = defaults.bool(forKey: Self.appLockKey)
    if let raw = defaults.string(forKey: Self.dohProviderKey),
      let provider = DoHProvider(rawValue: raw)
    {
      preferredDoHProvider = provider
    }
  }

  private static let currentAccountKey = "preferences.currentAccountID"
  private static let appLockKey = "preferences.appLockEnabled"
  private static let dohProviderKey = "preferences.dohProvider"

  var currentAccountID: UUID? = nil {
    didSet {
      if let currentAccountID {
        defaults.set(currentAccountID.uuidString, forKey: Self.currentAccountKey)
      } else {
        defaults.removeObject(forKey: Self.currentAccountKey)
      }
    }
  }

  var appLockEnabled: Bool = false {
    didSet { defaults.set(appLockEnabled, forKey: Self.appLockKey) }
  }

  var preferredDoHProvider: DoHProvider = .aliyun {
    didSet { defaults.set(preferredDoHProvider.rawValue, forKey: Self.dohProviderKey) }
  }
}

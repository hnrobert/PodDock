import Foundation
import DNSPodKit
import Observation

/// Preferences store (UserDefaults; nothing secret — credentials live only in Keychain).
/// The privacy manifest already declares the C56D.1 UserDefaults reason.
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
    if let raw = defaults.string(forKey: Self.llmProviderKey),
      let kind = LLMProviderKind(rawValue: raw)
    {
      llmProvider = kind
    }
    if let raw = defaults.string(forKey: Self.llmModelKey) {
      llmModel = raw
    }
    if let raw = defaults.string(forKey: Self.llmBaseURLKey) {
      llmBaseURL = raw
    }
  }

  var llmProvider: LLMProviderKind = .anthropic {
    didSet { defaults.set(llmProvider.rawValue, forKey: Self.llmProviderKey) }
  }

  var llmModel: String = "" {
    didSet { defaults.set(llmModel, forKey: Self.llmModelKey) }
  }

  var llmBaseURL: String = "" {
    didSet { defaults.set(llmBaseURL, forKey: Self.llmBaseURLKey) }
  }

  private static let currentAccountKey = "preferences.currentAccountID"
  private static let appLockKey = "preferences.appLockEnabled"
  private static let dohProviderKey = "preferences.dohProvider"
  private static let llmProviderKey = "preferences.llmProvider"
  private static let llmModelKey = "preferences.llmModel"
  private static let llmBaseURLKey = "preferences.llmBaseURL"

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

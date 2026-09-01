import Foundation
import LocalAuthentication

/// App lock (Face ID / Touch ID / password, optional; LAContext).
@MainActor
@Observable
final class AppLockController {
  private let preferences: PreferencesStore
  private(set) var isLocked = false
  var unlockFailureMessage: String?

  init(preferences: PreferencesStore) {
    self.preferences = preferences
  }

  /// Lock at cold start when the setting is on
  func engageIfNeeded() {
    if preferences.appLockEnabled {
      isLocked = true
    }
  }

  /// Unlock immediately when the app-lock toggle turns off
  func clearLock() {
    isLocked = false
    unlockFailureMessage = nil
  }

  func unlock() async {
    let context = LAContext()
    do {
      let success = try await context.evaluatePolicy(
        .deviceOwnerAuthentication,
        localizedReason: String(localized: "Unlock PodDock to manage your DNS"))
      if success {
        isLocked = false
        unlockFailureMessage = nil
      } else {
        unlockFailureMessage = String(localized: "Verification failed")
      }
    } catch {
      unlockFailureMessage = error.localizedDescription
    }
  }
}

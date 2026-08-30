import Foundation
import LocalAuthentication

/// 应用锁(Face ID / Touch ID / 密码,可选开关;LAContext)。
@MainActor
@Observable
final class AppLockController {
  private let preferences: PreferencesStore
  private(set) var isLocked = false
  var unlockFailureMessage: String?

  init(preferences: PreferencesStore) {
    self.preferences = preferences
  }

  /// 冷启动时按设置上锁
  func engageIfNeeded() {
    if preferences.appLockEnabled {
      isLocked = true
    }
  }

  /// 关闭应用锁开关时立即解除锁定
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

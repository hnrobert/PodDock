import SwiftUI

/// 应用锁遮罩:Face ID / Touch ID / 密码解锁
struct AppLockView: View {
  @Environment(AppEnvironment.self) private var environment
  @State private var isAuthenticating = false

  var body: some View {
    VStack(spacing: 20) {
      Image(systemName: "lock.fill")
        .font(.system(size: 56))
        .foregroundStyle(.secondary)
      Text("PodDock 已锁定").font(.title3.bold())
      if let failure = environment.lock.unlockFailureMessage {
        Text(failure).font(.callout).foregroundStyle(.red)
      }
      Button {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        Task {
          await environment.lock.unlock()
          isAuthenticating = false
        }
      } label: {
        if isAuthenticating {
          ProgressView().controlSize(.small)
        } else {
          Label("解锁", systemImage: "faceid")
        }
      }
      .buttonStyle(.borderedProminent)
      .padding(.top, 8)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .interactiveDismissDisabled()
    .task {
      // 冷启动进入时自动弹一次生物识别
      guard !isAuthenticating else { return }
      isAuthenticating = true
      await environment.lock.unlock()
      isAuthenticating = false
    }
  }
}

import SwiftUI

/// App-lock overlay: Face ID / Touch ID / password unlock
struct AppLockView: View {
  @Environment(AppEnvironment.self) private var environment
  @State private var isAuthenticating = false

  var body: some View {
    VStack(spacing: 20) {
      Image(systemName: "lock.fill")
        .font(.system(size: 56))
        .foregroundStyle(.secondary)
      Text("PodDock Locked").font(.title3.bold())
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
          Label("Unlock", systemImage: "faceid")
        }
      }
      .buttonStyle(.borderedProminent)
      .padding(.top, 8)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .interactiveDismissDisabled()
    .task {
      // Prompt biometric auth once when shown at cold start
      guard !isAuthenticating else { return }
      isAuthenticating = true
      await environment.lock.unlock()
      isAuthenticating = false
    }
  }
}

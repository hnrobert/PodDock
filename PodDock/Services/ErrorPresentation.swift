import Foundation
import DNSPodKit

extension DNSPodError {
  /// App-level error text: English keys + String Catalog (zh-Hans), following the system language.
  /// The Kit's Chinese localizedDescription only serves MCP/CLI hosts, never App UI.
  var uiMessage: String {
    switch self {
    case .transport(let detail):
      String(localized: "Network request failed: \(detail)")
    case .api(let code, let message):
      String(localized: "API error (\(code)): \(message)")
    case .remarkFailed(let underlying):
      String(localized: "Operation succeeded, but saving the remark failed (\(underlying.uiMessage))")
    case .notImplemented(let what):
      String(localized: "Not implemented: \(what)")
    case .invalidResponse(let detail):
      String(localized: "Unexpected response format: \(detail)")
    }
  }
}

/// UI text for any error: DNSPodError goes through the localized mapping;
/// everything else (KeychainError, LAContext, …) already localizes via localizedDescription.
/// Named to avoid the models' `errorMessage` property.
func describeError(_ error: Error) -> String {
  (error as? DNSPodError)?.uiMessage ?? error.localizedDescription
}

import Foundation
import DNSPodKit

extension DNSPodError {
  /// App 层错误文案:英文键 + String Catalog(zh-Hans 翻译),随系统语言。
  /// Kit 内部的中文 `localizedDescription` 只服务 MCP / CLI 宿主,不进 App UI。
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

/// 任意错误的 UI 文案:DNSPodError 走本地化映射;
/// 其余(KeychainError、LAContext 等系统错误)的 localizedDescription 本身随系统语言。
/// 命名避开模型里的 `errorMessage` 存储属性。
func describeError(_ error: Error) -> String {
  (error as? DNSPodError)?.uiMessage ?? error.localizedDescription
}

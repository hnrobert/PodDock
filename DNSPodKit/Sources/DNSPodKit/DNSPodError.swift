import Foundation

/// Unified error contract: impls normalize their errors here; the App knows only this.
/// remarkFailed nests itself — it must be indirect (recursive enums otherwise crash the compiler).
public indirect enum DNSPodError: Error, Sendable {
  /// Network/decoding failure (request never landed or response unparseable)
  case transport(String)
  /// API business error (status.code != 1 / Error.Code)
  case api(code: Int, message: String)
  /// Main op succeeded but the remark write failed (non-atomic pair) — UI shows a non-blocking notice and refreshes
  case remarkFailed(underlying: DNSPodError)
  /// This impl hasn't implemented the op yet (TC3 placeholder phase)
  case notImplemented(String)
  /// Response decodes but not into the expected shape
  case invalidResponse(String)

  /// Known auth-failure codes (bad/expired credentials); the App kicks back to Add Account on these.
  /// Code table to be completed from M1 real fixtures; covers what the reference surfaced for now.
  public var isAuthenticationFailure: Bool {
    switch self {
    case .api(let code, _):
      // 1 success / 2 system errors … auth-related: 6 wrong password, 7 invalid token, 8 expired token,
      // 9 token disabled, 16 account disabled, 30 unauthorized; 401 = DNSPod HTTP-level auth failure
      //(to be corrected against real fixtures)
      return [6, 7, 8, 9, 16, 30, 401].contains(code)
    case .remarkFailed(let underlying):
      return underlying.isAuthenticationFailure
    default:
      return false
    }
  }
}

extension DNSPodError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .transport(let detail):
      "网络请求失败:\(detail)"
    case .api(let code, let message):
      "API 错误(\(code)):\(message)"
    case .remarkFailed(let underlying):
      "操作已成功,但备注保存失败(\(underlying.localizedDescription))"
    case .notImplemented(let what):
      "尚未实现:\(what)"
    case .invalidResponse(let detail):
      "响应格式异常:\(detail)"
    }
  }
}

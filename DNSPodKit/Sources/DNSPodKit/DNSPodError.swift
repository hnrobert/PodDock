import Foundation

/// 统一错误契约:各 API 实现负责把自己的错误形态归一到这里,App 层只认它。
/// remarkFailed 直接嵌套自身,必须 indirect(否则递归枚举编译崩)。
public indirect enum DNSPodError: Error, Sendable {
  /// 网络/解码层失败(请求未成功送达或响应无法解析)
  case transport(String)
  /// API 返回业务错误(status.code != 1 / Error.Code)
  case api(code: Int, message: String)
  /// 主操作成功但备注写入失败(非原子的两次调用)——UI 非阻塞提示并刷新列表
  case remarkFailed(underlying: DNSPodError)
  /// 该实现未实现此操作(如 TC3 占位期)
  case notImplemented(String)
  /// 响应可解码但结构不符合预期
  case invalidResponse(String)

  /// 已知认证失败错误码(凭据失效/格式错),App 据此踢回添加账户页。
  /// 错误码表随 M1 真实 fixture 补全,先覆盖参考实现可见的行为。
  public var isAuthenticationFailure: Bool {
    switch self {
    case .api(let code, _):
      // 1 成功 / 2 系统错误区 …常用认证相关:6 密码错、7 Token 无效、8 Token 过期、
      // 9 Token 被禁用、16 账号被禁用、30 未授权(以实测 fixture 修正)
      return [6, 7, 8, 9, 16, 30].contains(code)
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

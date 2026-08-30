import Foundation

/// PodDockMCP 服务配置(双宿主共用)。
///
/// **服务器启动零凭据**:DNSPod Token 不在启动时内置(不用 DNSPOD_TOKEN),
/// 由 MCP 客户端在会话内调用 `dnspod_login` 工具认证,凭据绑定到该
/// `Mcp-Session-Id` 会话,后续工具调用全部使用会话对应的 client。
public struct MCPServerConfiguration: Sendable {
  /// 监听地址。Linux 部署默认 0.0.0.0;App 内嵌恒为 127.0.0.1
  public var host: String
  public var port: Int
  /// 可选:端点级 Bearer 保护(Authorization: Bearer <token>),与 dnspod_login 的
  /// 账户认证相互独立——前者保护 MCP 端点本身,后者绑定 DNSPod 凭据
  public var bearerToken: String?

  public init(
    host: String = "0.0.0.0",
    port: Int = 28100,
    bearerToken: String? = nil
  ) {
    self.host = host
    self.port = port
    self.bearerToken = bearerToken
  }

  /// 环境变量装配(Linux 宿主):
  /// `PODDOCK_MCP_HOST`(默认 0.0.0.0)、`PODDOCK_MCP_PORT`(默认 28100)、`MCP_AUTH_TOKEN`(端点 Bearer)。
  /// 注意:DNSPOD_TOKEN 已不再使用——认证走 MCP 会话内的 dnspod_login 工具。
  public static func fromEnvironment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> MCPServerConfiguration {
    var config = MCPServerConfiguration()
    if let host = environment["PODDOCK_MCP_HOST"], !host.isEmpty {
      config.host = host
    }
    if let portText = environment["PODDOCK_MCP_PORT"], let port = Int(portText) {
      config.port = port
    }
    if let token = environment["MCP_AUTH_TOKEN"], !token.isEmpty {
      config.bearerToken = token
    }
    return config
  }
}

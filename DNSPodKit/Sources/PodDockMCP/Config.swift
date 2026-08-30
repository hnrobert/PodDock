import Foundation
import DNSPodKit

/// PodDockMCP 服务配置(双宿主共用)。
///
/// - Linux 宿主(poddock-mcp):全部来自环境变量
/// - macOS App 内嵌宿主:直接构造注入(端口/Bearer 由 App 决定,凭据用当前账户)
public struct MCPServerConfiguration: Sendable {
  /// 监听地址。Linux 部署默认 0.0.0.0;App 内嵌恒为 127.0.0.1
  public var host: String
  public var port: Int
  /// 可选 Bearer 保护(Authorization: Bearer <token>)
  public var bearerToken: String?
  /// 传统 API 凭据(仅 Linux 宿主需要;App 内嵌共享当前账户,不经过此字段)
  public var legacyTokenID: String?
  public var legacyTokenKey: String?

  public init(
    host: String = "0.0.0.0",
    port: Int = 28100,
    bearerToken: String? = nil,
    legacyTokenID: String? = nil,
    legacyTokenKey: String? = nil
  ) {
    self.host = host
    self.port = port
    self.bearerToken = bearerToken
    self.legacyTokenID = legacyTokenID
    self.legacyTokenKey = legacyTokenKey
  }

  public var isReady: Bool {
    legacyTokenID != nil && legacyTokenKey != nil
  }

  /// 环境变量装配(Linux 宿主):
  /// `DNSPOD_TOKEN`="ID,Token"(必填)、`PODDOCK_MCP_HOST`、`PODDOCK_MCP_PORT`、`MCP_AUTH_TOKEN`
  public static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> MCPServerConfiguration {
    var config = MCPServerConfiguration()
    if let pasted = environment["DNSPOD_TOKEN"], let parsed = Account.parse(pasted: pasted) {
      config.legacyTokenID = parsed.id
      config.legacyTokenKey = parsed.token
    }
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

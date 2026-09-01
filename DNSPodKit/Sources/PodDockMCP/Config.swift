import Foundation

/// PodDockMCP service configuration (shared by both hosts).
///
/// **Zero startup credentials**: no DNSPod token at boot (no DNSPOD_TOKEN),
/// clients authenticate via the in-session `dnspod_login` tool; credentials bind to that
/// session; later tool calls all use the client bound to it.
public struct MCPServerConfiguration: Sendable {
  /// Listen address. Linux defaults to 0.0.0.0; the app embed is always 127.0.0.1
  public var host: String
  public var port: Int
  /// Optional endpoint bearer (Authorization: Bearer <token>), independent of dnspod_login's
  /// independent of account auth — the former guards the MCP endpoint, the latter binds DNSPod credentials
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

  /// Environment wiring (Linux host):
  /// `PODDOCK_MCP_HOST` (default 0.0.0.0), `PODDOCK_MCP_PORT` (default 28100), `MCP_AUTH_TOKEN` (endpoint bearer).
  /// Note: DNSPOD_TOKEN is no longer used — auth happens via dnspod_login inside the MCP session.
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

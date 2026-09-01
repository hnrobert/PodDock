import Foundation
import DNSPodKit
import PodDockMCP

// poddock-mcp — Linux/server host.
//
// Streamable HTTP with zero startup credentials: no DNSPod token baked in via env,
// Clients authenticate via the in-session dnspod_login tool; credentials bind to that session.
//
//   swift run poddock-mcp
//   Optional: PODDOCK_MCP_HOST (default 0.0.0.0), PODDOCK_MCP_PORT (default 28100),
//        MCP_AUTH_TOKEN (endpoint bearer, independent of dnspod_login)
//
// Client hookup (Claude Code):
//   claude mcp add --transport http poddock http://<host>:<port>/mcp
//   then ask the model to call dnspod_login with your "ID,Token".

let configuration = MCPServerConfiguration.fromEnvironment()
let service = MCPServerService(configuration: configuration)

print("poddock-mcp 启动:http://\(configuration.host):\(configuration.port)/mcp")
print("认证方式:会话内调用 dnspod_login 工具提供 DNSPod Token(启动零凭据)。")
if configuration.bearerToken != nil {
  print("端点保护:已启用 MCP_AUTH_TOKEN Bearer。")
}
print("Ctrl+C 停止。")

try await service.run()

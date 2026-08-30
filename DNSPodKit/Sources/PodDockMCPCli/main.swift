import Foundation
import DNSPodKit
import PodDockMCP

// poddock-mcp —— Linux/服务器宿主。
//
// Streamable HTTP 服务,**启动零凭据**:DNSPod Token 不经环境变量内置,
// 由 MCP 客户端在会话内调用 dnspod_login 工具认证,凭据绑定该会话。
//
//   swift run poddock-mcp
//   可选:PODDOCK_MCP_HOST(默认 0.0.0.0)、PODDOCK_MCP_PORT(默认 28100)、
//        MCP_AUTH_TOKEN(端点级 Bearer 保护,与 dnspod_login 相互独立)
//
// 客户端接入(Claude Code):
//   claude mcp add --transport http poddock http://<host>:<port>/mcp
//   然后在会话里让模型调用 dnspod_login 提供你的 "ID,Token"。

let configuration = MCPServerConfiguration.fromEnvironment()
let service = MCPServerService(configuration: configuration)

print("poddock-mcp 启动:http://\(configuration.host):\(configuration.port)/mcp")
print("认证方式:会话内调用 dnspod_login 工具提供 DNSPod Token(启动零凭据)。")
if configuration.bearerToken != nil {
  print("端点保护:已启用 MCP_AUTH_TOKEN Bearer。")
}
print("Ctrl+C 停止。")

try await service.run()

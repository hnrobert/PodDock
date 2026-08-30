import Foundation
import DNSPodKit
import PodDockMCP

// poddock-mcp —— Linux/服务器宿主。
// Streamable HTTP 服务装配于 M3 落地(swift-sdk Server + Hummingbird);
// 当前先完成配置装配与启动自检,保证 executable 与依赖解析从 M0 起可用。

let configuration = MCPServerConfiguration.fromEnvironment()

guard configuration.isReady else {
  FileHandle.standardError.write(
    Data(
      """
      poddock-mcp: 缺少凭据。
      用法:DNSPOD_TOKEN="ID,Token" poddock-mcp
      可选:PODDOCK_MCP_HOST(默认 0.0.0.0)、PODDOCK_MCP_PORT(默认 28100)、MCP_AUTH_TOKEN(端点 Bearer)
      """.utf8))
  exit(1)
}

print("poddock-mcp 配置就绪:http://\(configuration.host):\(configuration.port)")
print("Streamable HTTP 服务装配于 M3 里程碑落地,当前仅做启动自检。")

import Foundation
import DNSPodKit
import PodDockMCP
import Observation

/// macOS App 内嵌 MCP 宿主:设置里开关;监听 127.0.0.1,自动生成 Bearer;
/// 与 App 共享当前账户与同一 DNSPodClient——外部 AI 客户端操作的就是 App 正在管的账号。
@MainActor
@Observable
final class MCPHostService {
  private weak var environment: AppEnvironment?

  private(set) var isRunning = false
  private(set) var errorMessage: String?
  private var handle: MCPServerService.HostHandle?
  private var runTask: Task<Void, Never>?

  /// 自动生成的端点 Bearer(与账户认证独立)
  private(set) var bearerToken: String

  private let service: MCPServerService

  init() {
    let token = UUID().uuidString
    bearerToken = token
    service = MCPServerService(
      configuration: MCPServerConfiguration(host: "127.0.0.1", port: 28100, bearerToken: token),
      makeClient: { tokenID, tokenKey in
        LegacyClient(tokenID: tokenID, tokenKey: tokenKey, lang: "en")
      })
  }

  func attach(environment: AppEnvironment) {
    self.environment = environment
  }

  var endpointURL: String { "http://127.0.0.1:28100/mcp" }

  /// 一键接入串(claude mcp add …)
  var connectCommand: String {
    "claude mcp add --transport http --header \"Authorization: Bearer \(bearerToken)\" poddock \(endpointURL)"
  }

  func start() async {
    guard !isRunning else { return }
    errorMessage = nil
    do {
      let handle = try await service.startHost()
      self.handle = handle
      isRunning = true
      runTask = Task.detached(priority: .background) {
        try? await handle.run()
      }
    } catch {
      errorMessage = describeError(error)
    }
  }

  func stop() async {
    guard isRunning else { return }
    await handle?.stop()
    handle = nil
    runTask?.cancel()
    runTask = nil
    isRunning = false
  }
}

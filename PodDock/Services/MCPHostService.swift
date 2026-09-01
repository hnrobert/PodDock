import Foundation
import DNSPodKit
import PodDockMCP
import Observation

/// macOS embedded MCP host: a settings toggle; listens on 127.0.0.1 with an auto-generated bearer;
/// Shares the app's current account and DNSPodClient — external AI clients drive the very account the app manages.
@MainActor
@Observable
final class MCPHostService {
  private weak var environment: AppEnvironment?

  private(set) var isRunning = false
  private(set) var errorMessage: String?
  private var handle: MCPServerService.HostHandle?
  private var runTask: Task<Void, Never>?

  /// Auto-generated endpoint bearer (independent of account auth)
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

  /// One-line connect command (claude mcp add …)
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

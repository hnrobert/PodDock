import Foundation
import NIOCore
import Hummingbird
import HTTPTypes
import ServiceLifecycle
import MCP
import DNSPodKit

/// MCP session-auth errors (distinct from ToolDispatch argument errors)
enum MCPAuthError: Error, LocalizedError {
  case notAuthenticated
  case missingParameter(String)

  var errorDescription: String? {
    switch self {
    case .notAuthenticated: "Not authenticated: call dnspod_login in this session first"
    case .missingParameter(let name): "Missing parameter: \(name)"
    }
  }
}

// MARK: - Session credential store

/// After dnspod_login succeeds, binds the DNSPodClient to the `Mcp-Session-Id` session;
/// later calls in the session reuse this client. Logout/disconnect clears it.
actor MCPSessionStore {
  struct SessionEntry: Sendable {
    let client: DNSPodClient
    let label: String
    let loginAt: Date
  }

  private var entries: [String: SessionEntry] = [:]

  func login(sessionID: String, client: DNSPodClient, label: String) {
    entries[sessionID] = SessionEntry(client: client, label: label, loginAt: Date())
  }

  func logout(sessionID: String) {
    entries[sessionID] = nil
  }

  func entry(for sessionID: String) -> SessionEntry? {
    entries[sessionID]
  }

  var sessionCount: Int { entries.count }
}

// MARK: - Connection pool

/// `StatefulHTTPServerTransport` is single-session (one transport = one Mcp-Session-Id),
/// Concurrent clients need one transport + Server each, dispatched by the returned session header.
actor MCPConnectionPool {
  struct Connection: Sendable {
    let transport: StatefulHTTPServerTransport
    let server: Server
    var lastUsed: Date
  }

  private var connections: [String: Connection] = [:]

  func makeConnection(
    makeServer: @escaping @Sendable (StatefulHTTPServerTransport) async -> Server
  ) async -> (transport: StatefulHTTPServerTransport, server: Server) {
    let transport = StatefulHTTPServerTransport()
    let server = await makeServer(transport)
    try? await server.start(transport: transport)
    return (transport, server)
  }

  /// After the initialize reply (headers carry the session id), register the connection under it
  func register(sessionID: String, transport: StatefulHTTPServerTransport, server: Server) {
    connections[sessionID] = Connection(transport: transport, server: server, lastUsed: Date())
  }

  func connection(for sessionID: String) -> (transport: StatefulHTTPServerTransport, server: Server)? {
    guard var connection = connections[sessionID] else { return nil }
    connection.lastUsed = Date()
    connections[sessionID] = connection
    return (connection.transport, connection.server)
  }

  func close(sessionID: String) async {
    if let connection = connections.removeValue(forKey: sessionID) {
      await connection.server.stop()
    }
  }

  /// Drop idle connections (client vanished without DELETE)
  func sweep(idleThreshold: TimeInterval) async -> Int {
    let cutoff = Date().addingTimeInterval(-idleThreshold)
    let stale = connections.filter { $0.value.lastUsed < cutoff }
    for (sessionID, connection) in stale {
      connections[sessionID] = nil
      await connection.server.stop()
    }
    return stale.count
  }
}

// MARK: - Service

/// Embeddable MCP Streamable HTTP service (shared by both hosts):
/// - Linux host: the poddock-mcp executable just calls `run()`
/// - macOS app embed: same service, injected with a client factory sharing the current account
///
/// Auth model: zero startup credentials; each MCP client session is independent — the client calls
/// `dnspod_login` (pasted "ID,Token" or split fields) → server validates via LegacyClient →
/// credentials bind to that Mcp-Session-Id → other tools fetch the client by session.
/// Optional MCP_AUTH_TOKEN endpoint bearer, independent of account auth.
public final class MCPServerService: Sendable {
  public let configuration: MCPServerConfiguration
  private let credentialStore = MCPSessionStore()
  private let pool = MCPConnectionPool()
  private let makeClient: @Sendable (_ tokenID: String, _ tokenKey: String) -> DNSPodClient

  /// - Parameters:
  ///   - makeClient: factory building the DNSPod client after login (default LegacyClient;
  ///     tests can inject a stub; the embedded host injects one sharing the current account)
  public init(
    configuration: MCPServerConfiguration = MCPServerConfiguration(),
    makeClient: @escaping @Sendable (String, String) -> DNSPodClient = {
      LegacyClient(tokenID: $0, tokenKey: $1)
    }
  ) {
    self.configuration = configuration
    self.makeClient = makeClient
  }

  // MARK: - Startup

  /// Embedded-host handle: run() serves until stopped, stop() triggers graceful shutdown (macOS app embed)
  public struct HostHandle: Sendable {
    let group: ServiceGroup

    public func run() async throws {
      try await group.run()
    }

    public func stop() async {
      await group.triggerGracefulShutdown()
    }
  }

  /// Assemble the Hummingbird app and serve (Linux host; embedded host uses startHost)
  public func run() async throws {
    // Idle sweep (hourly; connections unused for 1h get dropped)
    let pool = self.pool
    Task.detached {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(3600))
        _ = await pool.sweep(idleThreshold: 3600)
      }
    }

    try await makeApplication().runService()
  }

  /// Assemble without starting; the embedded host drives the ServiceGroup itself
  public func startHost() async throws -> HostHandle {
    HostHandle(group: ServiceGroup(services: [makeApplication()]))
  }

  private func makeApplication() -> some ApplicationProtocol {
    let router = Router()
    let service = self

    router.post("mcp") { request, _ -> Response in
      try await service.handle(request: request, hasBody: true)
    }
    router.get("mcp") { request, _ -> Response in
      try await service.handle(request: request, hasBody: false)
    }
    router.delete("mcp") { request, _ -> Response in
      try await service.handle(request: request, hasBody: false, closeAfter: true)
    }

    return Application(
      router: router,
      configuration: .init(address: .hostname(configuration.host, port: configuration.port))
    )
  }

  // MARK: - Request handling

  private func handle(request: Request, hasBody: Bool, closeAfter: Bool = false) async throws -> Response {
    var headers: [String: String] = [:]
    for field in request.headers {
      headers[String(describing: field.name)] = field.value
    }

    // Endpoint bearer (optional; independent of dnspod_login account auth)
    if let required = configuration.bearerToken {
      let provided = headers.first { $0.key.lowercased() == "authorization" }?.value
      guard provided == "Bearer \(required)" else {
        return Response(status: .unauthorized, body: .init())
      }
    }

    let sessionID = headers.first { $0.key.lowercased() == HTTPHeaderName.sessionID.lowercased() }?.value

    let transport: StatefulHTTPServerTransport
    var newConnection: (transport: StatefulHTTPServerTransport, server: Server)?
    if let sessionID, let connection = await pool.connection(for: sessionID) {
      transport = connection.transport
    } else {
      // New client: build a dedicated transport + Server; register under its session id once initialize replies
      let connection = await pool.makeConnection { transport in
        await self.makeServer(transport: transport)
      }
      transport = connection.transport
      newConnection = connection
    }

    var body: Data?
    if hasBody {
      var request = request
      let buffer = try await request.collectBody(upTo: 1 << 22)
      if buffer.readableBytes > 0 {
        body = Data(buffer.readableBytesView)
      }
    }

    let mcpRequest = MCP.HTTPRequest(
      method: request.method.rawValue,
      headers: headers,
      body: body,
      path: request.uri.path)
    let mcpResponse = await transport.handleRequest(mcpRequest)

    if let newConnection {
      let assigned = mcpResponse.headers
        .first { $0.key.lowercased() == HTTPHeaderName.sessionID.lowercased() }?.value
      if let assigned, !assigned.isEmpty {
        await pool.register(
          sessionID: assigned, transport: newConnection.transport, server: newConnection.server)
      }
    }
    if closeAfter, let sessionID {
      await pool.close(sessionID: sessionID)
      await credentialStore.logout(sessionID: sessionID)
    }

    return Self.hummingbirdResponse(from: mcpResponse)
  }

  // MARK: - Server assembly

  private func makeServer(transport: StatefulHTTPServerTransport) async -> Server {
    let server = Server(
      name: "poddock-mcp",
      version: "0.1.0",
      title: "PodDock MCP",
      instructions: "DNSPod 域名与解析记录管理。首次使用请先调用 dnspod_login 提供 DNSPod Token(格式 ID,Token),之后即可使用全部工具。",
      capabilities: .init(tools: .init(listChanged: false))
    )
    await registerHandlers(on: server)
    return server
  }

  private func registerHandlers(on server: Server) async {
    let sessions = self.credentialStore
    let makeClient = self.makeClient

    // Tool catalog (MCPToolCatalog single source + auth tools)
    await server.withMethodHandler(ListTools.self) { _ in
      let catalogTools = MCPToolCatalog.all.map { tool in
        Tool(
          name: tool.name,
          title: tool.name,
          description: tool.description,
          inputSchema: tool.inputSchema.mcpValue,
          annotations: .init(
            readOnlyHint: tool.isReadOnly,
            destructiveHint: tool.isDestructive
          ))
      }
      let authTools = [
        Tool(
          name: "dnspod_login",
          title: "DNSPod 登录",
          description: "提供 DNSPod API Token 完成本会话认证(整串 \"ID,Token\" 粘贴,或分字段)。认证后才能使用其余工具。",
          inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
              "token": .string("整串 Token:\"ID,Token\"(与 token_id/token_key 二选一)"),
              "token_id": .string("Token ID(与 token 二选一)"),
              "token_key": .string("Token Key"),
            ]),
            "additionalProperties": .bool(false),
          ]),
          annotations: .init(readOnlyHint: true, openWorldHint: false)),
        Tool(
          name: "dnspod_logout",
          title: "DNSPod 登出",
          description: "清除本会话绑定的 DNSPod 凭据",
          inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
            "additionalProperties": .bool(false),
          ]),
          annotations: .init(readOnlyHint: true, openWorldHint: false)),
      ]
      return ListTools.Result(tools: authTools + catalogTools)
    }

    // Tool calls
    await server.withMethodHandler(CallTool.self) { params in
      do {
        return try await Self.handleToolCall(
          params: params, sessions: sessions, makeClient: makeClient)
      } catch let error as MCPAuthError {
        return CallTool.Result(content: [.text(error.localizedDescription)], isError: true)
      } catch let error as DNSPodError {
        return CallTool.Result(content: [.text(error.localizedDescription)], isError: true)
      } catch {
        return CallTool.Result(content: [.text(error.localizedDescription)], isError: true)
      }
    }
  }

  /// One tool call: auth tools go through the session store; business tools require an authenticated session
  static func handleToolCall(
    params: CallTool.Parameters,
    sessions: MCPSessionStore,
    makeClient: @Sendable (String, String) -> DNSPodClient
  ) async throws -> CallTool.Result {
    let args = params.arguments ?? [:]
    let sessionID = Server.currentHandlerContext?.httpContext?.header(HTTPHeaderName.sessionID)

    func requireSessionID() throws -> String {
      guard let sessionID, !sessionID.isEmpty else {
        throw MCPAuthError.notAuthenticated
      }
      return sessionID
    }

    switch params.name {
    case "dnspod_login":
      let parsed: (id: String, token: String)
      if let pasted = args["token"]?.stringValue, let split = Account.parse(pasted: pasted) {
        parsed = split
      } else if let id = args["token_id"]?.stringValue, let key = args["token_key"]?.stringValue,
        !id.isEmpty, !key.isEmpty
      {
        parsed = (id, key)
      } else {
        throw MCPAuthError.missingParameter("token(或 token_id + token_key)")
      }

      let client = makeClient(parsed.id, parsed.token)
      let domains = try await client.listDomains()  // error_on_empty=no: list success means valid credentials
      let sessionID = try requireSessionID()
      let label = Account.defaultLabel(tokenID: parsed.id)
      await sessions.login(sessionID: sessionID, client: client, label: label)
      return CallTool.Result(
        content: [.text("认证成功:\(label),账户下 \(domains.count) 个域名。本会话已绑定,可使用其余工具。")],
        isError: false)

    case "dnspod_logout":
      let sessionID = try requireSessionID()
      await sessions.logout(sessionID: sessionID)
      return CallTool.Result(content: [.text("已登出,会话凭据已清除。")], isError: false)

    default:
      let sessionID = try requireSessionID()
      guard let entry = await sessions.entry(for: sessionID) else {
        throw MCPAuthError.notAuthenticated
      }
      let output = try await ToolDispatch.dispatch(
        name: params.name,
        arguments: MCPArgumentBridge.convert(params.arguments),
        client: entry.client)
      return CallTool.Result(content: [.text(output)], isError: false)
    }
  }

  // MARK: - Response mapping

  /// MCP HTTPResponse → Hummingbird Response (SSE pass-through included)
  nonisolated static func hummingbirdResponse(from mcpResponse: MCP.HTTPResponse) -> Response {
    var fields = HTTPFields()
    for (name, value) in mcpResponse.headers {
      // MCP response headers are all standard names; skip invalid ones (theoretical)
      if let fieldName = HTTPField.Name(name) {
        fields.append(HTTPField(name: fieldName, value: value))
      }
    }
    let status = HTTPResponse.Status(code: mcpResponse.statusCode)

    switch mcpResponse {
    case .data(let data, _):
      return Response(
        status: status, headers: fields,
        body: .init(byteBuffer: ByteBuffer(bytes: data)))
    case .stream(let sseStream, _):
      // SSE: pipe the async stream into the response body (POST replies and GET long-poll alike)
      return Response(
        status: status, headers: fields,
        body: .init(contentLength: nil) { writer in
          for try await chunk in sseStream {
            try await writer.write(ByteBuffer(bytes: chunk))
          }
        })
    default:
      return Response(status: status, headers: fields, body: .init())
    }
  }
}

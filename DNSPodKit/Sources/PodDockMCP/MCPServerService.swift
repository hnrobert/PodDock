import Foundation
import NIOCore
import Hummingbird
import HTTPTypes
import MCP
import DNSPodKit

// MARK: - 会话凭据仓

/// dnspod_login 验证通过后,把 DNSPodClient 绑定到 `Mcp-Session-Id` 会话;
/// 后续同会话的工具调用全部使用这份 client。登出/断开即清除。
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

// MARK: - 连接池

/// `StatefulHTTPServerTransport` 是单会话 transport(一个 transport 一个 Mcp-Session-Id),
/// 多客户端并发访问必须每会话一套 transport + Server,按客户端回传的会话头分发。
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

  /// initialize 响应回来后(响应头带会话号),把连接登记到该会话号下
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

  /// 清理空闲连接(客户端异常断开、未发 DELETE 的情况)
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

// MARK: - 服务

/// 可嵌入的 MCP Streamable HTTP 服务(双宿主共用):
/// - Linux 宿主:poddock-mcp executable 直接 `run()`
/// - macOS App 内嵌:同一服务,注入共享当前账户的 client 工厂
///
/// 认证模型:**启动零凭据**;每个 MCP 客户端会话独立——客户端在会话内调用
/// `dnspod_login`(整串 "ID,Token" 或分字段)→ 服务端用 LegacyClient 验证 →
/// 凭据绑定该 Mcp-Session-Id → 其余工具按会话取 client。
/// 可选 MCP_AUTH_TOKEN 做端点级 Bearer,与账户认证相互独立。
public final class MCPServerService: Sendable {
  public let configuration: MCPServerConfiguration
  private let credentialStore = MCPSessionStore()
  private let pool = MCPConnectionPool()
  private let makeClient: @Sendable (_ tokenID: String, _ tokenKey: String) -> DNSPodClient

  /// - Parameters:
  ///   - makeClient: 认证通过后构造 DNSPod 客户端的工厂(默认 LegacyClient;
  ///     测试可注入 stub;App 内嵌宿主可注入共享当前账户的实现)
  public init(
    configuration: MCPServerConfiguration = MCPServerConfiguration(),
    makeClient: @escaping @Sendable (String, String) -> DNSPodClient = {
      LegacyClient(tokenID: $0, tokenKey: $1)
    }
  ) {
    self.configuration = configuration
    self.makeClient = makeClient
  }

  // MARK: - 启动

  /// 组装 Hummingbird 应用并阻塞服务(Linux 宿主用;App 内嵌宿主放后台 Task)
  public func run() async throws {
    // 空闲连接回收(每小时一次,1 小时未用即清)
    let pool = self.pool
    Task.detached {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(3600))
        _ = await pool.sweep(idleThreshold: 3600)
      }
    }

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

    let app = Application(
      router: router,
      configuration: .init(address: .hostname(configuration.host, port: configuration.port))
    )
    try await app.runService()
  }

  // MARK: - 请求处理

  private func handle(request: Request, hasBody: Bool, closeAfter: Bool = false) async throws -> Response {
    var headers: [String: String] = [:]
    for field in request.headers {
      headers[String(describing: field.name)] = field.value
    }

    // 端点级 Bearer(可选;与 dnspod_login 的账户认证相互独立)
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
      // 新客户端:建一套专属 transport + Server,initialize 响应后再按其会话号登记
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

  // MARK: - Server 组装

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

    // 工具目录(MCPToolCatalog 单一契约源 + 认证工具)
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

    // 工具调用
    await server.withMethodHandler(CallTool.self) { params in
      do {
        return try await Self.handleToolCall(
          params: params, sessions: sessions, makeClient: makeClient)
      } catch let error as MCPToolDispatch.DispatchError {
        return CallTool.Result(content: [.text(error.localizedDescription)], isError: true)
      } catch let error as DNSPodError {
        return CallTool.Result(content: [.text(error.localizedDescription)], isError: true)
      } catch {
        return CallTool.Result(content: [.text(error.localizedDescription)], isError: true)
      }
    }
  }

  /// 单次工具调用:认证工具走会话仓,业务工具要求会话已认证
  static func handleToolCall(
    params: CallTool.Parameters,
    sessions: MCPSessionStore,
    makeClient: @Sendable (String, String) -> DNSPodClient
  ) async throws -> CallTool.Result {
    let args = params.arguments ?? [:]
    let sessionID = Server.currentHandlerContext?.httpContext?.header(HTTPHeaderName.sessionID)

    func requireSessionID() throws -> String {
      guard let sessionID, !sessionID.isEmpty else {
        throw MCPToolDispatch.DispatchError.notAuthenticated
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
        throw MCPToolDispatch.DispatchError.missingParameter("token(或 token_id + token_key)")
      }

      let client = makeClient(parsed.id, parsed.token)
      let domains = try await client.listDomains()  // error_on_empty=no:列表成功即凭据有效
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
        throw MCPToolDispatch.DispatchError.notAuthenticated
      }
      let output = try await MCPToolDispatch.dispatch(
        name: params.name, arguments: params.arguments, client: entry.client)
      return CallTool.Result(content: [.text(output)], isError: false)
    }
  }

  // MARK: - 响应映射

  /// MCP HTTPResponse → Hummingbird Response(含 SSE 流式透传)
  nonisolated static func hummingbirdResponse(from mcpResponse: MCP.HTTPResponse) -> Response {
    var fields = HTTPFields()
    for (name, value) in mcpResponse.headers {
      // MCP 的响应头都是标准名;非法名(理论不出现)跳过
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
      // SSE:把 async 流写进响应体(POST 响应与 GET 长连接共用)
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

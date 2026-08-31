import Foundation
import DNSPodKit

// MARK: - Anthropic 原生 /v1/messages(Swift 无官方 SDK,原生 HTTP 实现)

struct AnthropicClient: LLMProviding {
  static let defaultBaseURL = "https://api.anthropic.com"
  static let defaultModel = "claude-opus-5"
  static let apiVersion = "2023-06-01"

  let apiKey: String
  let model: String
  let baseURL: String
  private let transport: HTTPTransport

  init(apiKey: String, model: String = AnthropicClient.defaultModel, baseURL: String = AnthropicClient.defaultBaseURL, transport: HTTPTransport = URLSessionTransport(timeout: 120)) {
    self.apiKey = apiKey
    self.model = model
    self.baseURL = baseURL
    self.transport = transport
  }

  func complete(system: String, messages: [LLMMessage], tools: [LLMToolDefinition]) async throws -> LLMResponse {
    var body: [String: Any] = [
      "model": model,
      "max_tokens": 16000,
      "messages": messages.map(Self.encodeMessage),
    ]
    if !system.isEmpty { body["system"] = system }
    if !tools.isEmpty {
      body["tools"] = tools.map { tool in
        [
          "name": tool.name,
          "description": tool.description,
          "input_schema": tool.inputSchema.anyValue,
        ]
      }
    }

    let data = try await post("\(baseURL)/v1/messages", body)
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let content = object["content"] as? [[String: Any]]
    else { throw LLMError.invalidResponse("missing content array") }

    var text = ""
    var toolCalls: [LLMToolCall] = []
    for block in content {
      switch block["type"] as? String {
      case "text":
        text += (block["text"] as? String ?? "")
      case "tool_use":
        guard let id = block["id"] as? String,
          let name = block["name"] as? String,
          let input = block["input"] as? [String: Any],
          let arguments = JSONValue(any: input)?.objectValue
        else { continue }
        toolCalls.append(LLMToolCall(id: id, name: name, arguments: arguments))
      default:
        break
      }
    }
    return LLMResponse(text: text, toolCalls: toolCalls, stopReason: object["stop_reason"] as? String)
  }

  private func post(_ url: String, _ body: [String: Any]) async throws -> Data {
    // SE-0461:非隔离 async 继承调用方 actor,LLM 往返必须离开主线程
    let request = HTTPRequest(
      url: URL(string: url)!,
      method: "POST",
      headers: [
        "Content-Type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": Self.apiVersion,
      ],
      body: try JSONSerialization.data(withJSONObject: body))
    let response = try await Task.detached(priority: .userInitiated) {
      try await transport.send(request)
    }.value
    guard (200..<300).contains(response.statusCode) else {
      let body = String(decoding: response.body.prefix(400), as: UTF8.self)
      throw LLMError.http(response.statusCode, body)
    }
    return response.body
  }

  private static func encodeMessage(_ message: LLMMessage) -> [String: Any] {
    [
      "role": message.role.rawValue,
      "content": message.blocks.compactMap(encodeBlock),
    ]
  }

  private static func encodeBlock(_ block: LLMContentBlock) -> [String: Any]? {
    switch block {
    case .text(let text):
      ["type": "text", "text": text]
    case .toolUse(let id, let name, let arguments):
      [
        "type": "tool_use",
        "id": id,
        "name": name,
        "input": JSONValue.object(arguments).anyValue,
      ]
    case .toolResult(let id, let iserror, let content):
      [
        "type": "tool_result",
        "tool_use_id": id,
        "is_error": iserror,
        "content": content,
      ]
    }
  }
}

// MARK: - OpenAI 兼容 /chat/completions(自定义 base URL)

struct OpenAICompatClient: LLMProviding {
  static let defaultBaseURL = "https://api.openai.com/v1"
  static let defaultModel = "gpt-5"

  let apiKey: String
  let model: String
  let baseURL: String
  private let transport: HTTPTransport

  init(apiKey: String, model: String = OpenAICompatClient.defaultModel, baseURL: String = OpenAICompatClient.defaultBaseURL, transport: HTTPTransport = URLSessionTransport(timeout: 120)) {
    self.apiKey = apiKey
    self.model = model
    self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
    self.transport = transport
  }

  func complete(system: String, messages: [LLMMessage], tools: [LLMToolDefinition]) async throws -> LLMResponse {
    var encoded: [[String: Any]] = []
    if !system.isEmpty {
      encoded.append(["role": "system", "content": system])
    }
    for message in messages {
      encoded.append(contentsOf: Self.encodeMessage(message))
    }
    var body: [String: Any] = [
      "model": model,
      "messages": encoded,
    ]
    if !tools.isEmpty {
      body["tools"] = tools.map { tool in
        [
          "type": "function",
          "function": [
            "name": tool.name,
            "description": tool.description,
            "parameters": tool.inputSchema.anyValue,
          ] as [String: Any],
        ]
      }
    }

    let data = try await post("\(baseURL)/chat/completions", body)
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let choices = object["choices"] as? [[String: Any]],
      let message = choices.first?["message"] as? [String: Any]
    else { throw LLMError.invalidResponse("missing choices[0].message") }

    let text = message["content"] as? String ?? ""
    var toolCalls: [LLMToolCall] = []
    for call in message["tool_calls"] as? [[String: Any]] ?? [] {
      guard let id = call["id"] as? String,
        let function = call["function"] as? [String: Any],
        let name = function["name"] as? String
      else { continue }
      let argumentsText = function["arguments"] as? String ?? "{}"
      let arguments =
        ((try? JSONSerialization.jsonObject(with: Data(argumentsText.utf8))) as? [String: Any])
        .flatMap { JSONValue(any: $0)?.objectValue } ?? [:]
      toolCalls.append(LLMToolCall(id: id, name: name, arguments: arguments))
    }
    return LLMResponse(text: text, toolCalls: toolCalls, stopReason: object["choices"].flatMap { _ in nil } ?? "stop")
  }

  private func post(_ url: String, _ body: [String: Any]) async throws -> Data {
    let request = HTTPRequest(
      url: URL(string: url)!,
      method: "POST",
      headers: [
        "Content-Type": "application/json",
        "Authorization": "Bearer \(apiKey)",
      ],
      body: try JSONSerialization.data(withJSONObject: body))
    let response = try await Task.detached(priority: .userInitiated) {
      try await transport.send(request)
    }.value
    guard (200..<300).contains(response.statusCode) else {
      let body = String(decoding: response.body.prefix(400), as: UTF8.self)
      throw LLMError.http(response.statusCode, body)
    }
    return response.body
  }

  /// 一条 LLMMessage 可能展开为多条 OpenAI 消息(assistant 工具调用与 tool 结果是独立消息)
  private static func encodeMessage(_ message: LLMMessage) -> [[String: Any]] {
    var result: [[String: Any]] = []
    var pendingToolCalls: [[String: Any]] = []
    var textParts: [String] = []

    func flushAssistant() {
      guard !pendingToolCalls.isEmpty || !textParts.isEmpty else { return }
      var encoded: [String: Any] = [
        "role": "assistant",
        "content": textParts.joined(separator: "\n").isEmpty ? nil : textParts.joined(separator: "\n"),
      ]
      if !pendingToolCalls.isEmpty {
        encoded["tool_calls"] = pendingToolCalls
      }
      result.append(encoded)
      pendingToolCalls = []
      textParts = []
    }

    for block in message.blocks {
      switch block {
      case .text(let text):
        if message.role == .user {
          result.append(["role": "user", "content": text])
        } else {
          textParts.append(text)
        }
      case .toolUse(let id, let name, let arguments):
        pendingToolCalls.append([
          "id": id,
          "type": "function",
          "function": [
            "name": name,
            "arguments": String(data: try! JSONSerialization.data(withJSONObject: JSONValue.object(arguments).anyValue), encoding: .utf8) ?? "{}",
          ] as [String: Any],
        ])
      case .toolResult(let id, let iserror, let content):
        flushAssistant()
        result.append([
          "role": "tool",
          "tool_call_id": id,
          "content": iserror ? "error: \(content)" : content,
        ])
      }
    }
    flushAssistant()
    return result
  }
}

// MARK: - 工厂

enum LLMClientFactory {
  /// 按设置构造;未配置(无 key)返回 nil
  static func make(kind: LLMProviderKind, apiKey: String?, model: String, baseURL: String) -> LLMProviding? {
    guard let apiKey, !apiKey.isEmpty else { return nil }
    let model = model.isEmpty ? nil : model
    switch kind {
    case .anthropic:
      return AnthropicClient(
        apiKey: apiKey,
        model: model ?? AnthropicClient.defaultModel,
        baseURL: baseURL.isEmpty ? AnthropicClient.defaultBaseURL : baseURL)
    case .openAICompatible:
      return OpenAICompatClient(
        apiKey: apiKey,
        model: model ?? OpenAICompatClient.defaultModel,
        baseURL: baseURL.isEmpty ? OpenAICompatClient.defaultBaseURL : baseURL)
    }
  }
}

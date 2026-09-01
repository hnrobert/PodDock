import Foundation
import DNSPodKit

// MARK: - LLM abstraction (protocol-agnostic message/tool/response shapes)

enum LLMProviderKind: String, CaseIterable, Identifiable, Sendable {
  case anthropic
  case openAICompatible = "openai"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .anthropic: "Anthropic"
    case .openAICompatible: "OpenAI-compatible"
    }
  }
}

/// Tool definition (LLM-side shape of MCPToolCatalog; shared by both protocols)
struct LLMToolDefinition: Sendable {
  let name: String
  let description: String
  let inputSchema: JSONValue

  init(_ tool: MCPToolDefinition) {
    name = tool.name
    description = tool.description
    inputSchema = tool.inputSchema
  }

  static var catalog: [LLMToolDefinition] {
    MCPToolCatalog.all.map(LLMToolDefinition.init)
  }
}

/// Message content blocks
enum LLMContentBlock: Sendable {
  case text(String)
  case toolUse(id: String, name: String, arguments: [String: JSONValue])
  case toolResult(id: String, iserror: Bool, content: String)
}

struct LLMMessage: Sendable {
  let role: LLMRole
  let blocks: [LLMContentBlock]

  enum LLMRole: String, Sendable {
    case user
    case assistant
  }

  static func user(_ text: String) -> LLMMessage {
    LLMMessage(role: .user, blocks: [.text(text)])
  }
}

struct LLMToolCall: Sendable {
  let id: String
  let name: String
  let arguments: [String: JSONValue]
}

struct LLMResponse: Sendable {
  let text: String
  let toolCalls: [LLMToolCall]
  var stopReason: String?

  var wantsTools: Bool { !toolCalls.isEmpty }
}

enum LLMError: Error, LocalizedError {
  case notConfigured
  case http(Int, String)
  case invalidResponse(String)

  var errorDescription: String? {
    switch self {
    case .notConfigured:
      String(localized: "LLM provider is not configured — set it up in Settings")
    case .http(let code, let body):
      String(localized: "LLM request failed (HTTP \(code)): \(body)")
    case .invalidResponse(let detail):
      String(localized: "Unexpected LLM response: \(detail)")
    }
  }
}

// MARK: - Provider protocol

protocol LLMProviding: Sendable {
  func complete(system: String, messages: [LLMMessage], tools: [LLMToolDefinition]) async throws -> LLMResponse
}

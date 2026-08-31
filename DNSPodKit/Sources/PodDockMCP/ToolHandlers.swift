import Foundation
import MCP
import DNSPodKit

// MARK: - JSONValue ↔ MCP Value

extension JSONValue {
  /// Kit 的 JSON 树转 MCP 的 Value(工具 schema 的单一契约源 → MCP 工具定义)
  var mcpValue: Value {
    switch self {
    case .null: .null
    case .bool(let bool): .bool(bool)
    case .int(let int): .int(int)
    case .double(let double): .double(double)
    case .string(let string): .string(string)
    case .array(let array): .array(array.map(\.mcpValue))
    case .object(let object): .object(object.mapValues(\.mcpValue))
    }
  }

  /// MCP Value → Kit 的 JSON 树(工具调用参数 → ToolDispatch)
  init(mcp value: Value) {
    switch value {
    case .null: self = .null
    case .bool(let bool): self = .bool(bool)
    case .int(let int): self = .int(int)
    case .double(let double): self = .double(double)
    case .string(let string): self = .string(string)
    case .data(_, let data): self = .string(data.base64EncodedString())
    case .array(let array): self = .array(array.map { JSONValue(mcp: $0) })
    case .object(let object): self = .object(object.mapValues { JSONValue(mcp: $0) })
    }
  }
}

/// MCP 参数([String: Value])→ ToolDispatch 参数([String: JSONValue])
enum MCPArgumentBridge {
  static func convert(_ arguments: [String: Value]?) -> [String: JSONValue] {
    (arguments ?? [:]).mapValues { JSONValue(mcp: $0) }
  }
}

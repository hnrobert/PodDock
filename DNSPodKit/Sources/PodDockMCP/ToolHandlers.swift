import Foundation
import MCP
import DNSPodKit

// MARK: - JSONValue ↔ MCP Value

extension JSONValue {
  /// Kit JSON tree → MCP Value (catalog schema → MCP tool definitions)
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

  /// MCP Value → Kit JSON tree (tool arguments → ToolDispatch)
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

/// MCP arguments ([String: Value]) → ToolDispatch arguments ([String: JSONValue])
enum MCPArgumentBridge {
  static func convert(_ arguments: [String: Value]?) -> [String: JSONValue] {
    (arguments ?? [:]).mapValues { JSONValue(mcp: $0) }
  }
}

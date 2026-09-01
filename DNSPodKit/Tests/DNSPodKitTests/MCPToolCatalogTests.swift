import Testing
import Foundation
@testable import DNSPodKit

@Suite("MCP tool catalog (single source of truth)")
struct MCPToolCatalogTests {
  @Test("12 tools with unique names")
  func catalogShape() {
    #expect(MCPToolCatalog.all.count == 12)
    #expect(Set(MCPToolCatalog.all.map(\.name)).count == MCPToolCatalog.all.count)
  }

  @Test("every schema is an object with required ⊆ properties")
  func schemaWellFormed() throws {
    for tool in MCPToolCatalog.all {
      guard case .object(let schema) = tool.inputSchema else {
        Issue.record("\(tool.name): inputSchema 不是 object")
        continue
      }
      #expect(schema["type"] == .string("object"), "\(tool.name): type != object")

      guard case .object(let properties)? = schema["properties"] else {
        Issue.record("\(tool.name): 缺 properties")
        continue
      }
      guard case .array(let required)? = schema["required"] else {
        Issue.record("\(tool.name): 缺 required")
        continue
      }
      for case .string(let name) in required {
        #expect(properties[name] != nil, "\(tool.name): required 字段 \(name) 不在 properties 里")
      }
    }
  }

  @Test("JSONValue round-trips through JSONEncoder (usable as LLM tool definitions)")
  func jsonSerialization() throws {
    for tool in MCPToolCatalog.all {
      let data = try JSONEncoder().encode(tool.inputSchema)
      let roundTrip = try JSONDecoder().decode(JSONValue.self, from: data)
      #expect(roundTrip == tool.inputSchema, "\(tool.name): schema 序列化不往返")
    }
  }

  @Test("destructive flags land only on removal tools")
  func destructiveFlags() {
    let destructive = Set(MCPToolCatalog.all.filter(\.isDestructive).map(\.name))
    #expect(destructive == ["remove_domain", "remove_record"])
  }
}

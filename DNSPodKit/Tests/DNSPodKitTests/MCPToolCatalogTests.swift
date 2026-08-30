import Testing
import Foundation
@testable import DNSPodKit

@Suite("MCP 工具目录(单一契约源)")
struct MCPToolCatalogTests {
  @Test("12 件工具,名称唯一")
  func catalogShape() {
    #expect(MCPToolCatalog.all.count == 12)
    #expect(Set(MCPToolCatalog.all.map(\.name)).count == MCPToolCatalog.all.count)
  }

  @Test("每件工具的 schema 都是 object 且 required ⊆ properties")
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

  @Test("JSONValue 可被 JSONEncoder 序列化(LLM tool definition 直接用)")
  func jsonSerialization() throws {
    for tool in MCPToolCatalog.all {
      let data = try JSONEncoder().encode(tool.inputSchema)
      let roundTrip = try JSONDecoder().decode(JSONValue.self, from: data)
      #expect(roundTrip == tool.inputSchema, "\(tool.name): schema 序列化不往返")
    }
  }

  @Test("破坏性标注只落在删除类工具上")
  func destructiveFlags() {
    let destructive = Set(MCPToolCatalog.all.filter(\.isDestructive).map(\.name))
    #expect(destructive == ["remove_domain", "remove_record"])
  }
}

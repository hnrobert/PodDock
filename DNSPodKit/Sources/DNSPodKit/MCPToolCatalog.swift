import Foundation

// MARK: - 轻量 JSON 值树
//
// MCP 工具 schema 与 LLM tool definition 共用的 JSON 表示,
// 不引入任何第三方依赖,也不耦合 swift-sdk 类型(升级 SDK 只动 Server 层)。

public enum JSONValue: Sendable, Equatable {
  case null
  case bool(Bool)
  case int(Int)
  case double(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])
}

extension JSONValue: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let bool = try? container.decode(Bool.self) {
      self = .bool(bool)
    } else if let int = try? container.decode(Int.self) {
      self = .int(int)
    } else if let double = try? container.decode(Double.self) {
      self = .double(double)
    } else if let string = try? container.decode(String.self) {
      self = .string(string)
    } else if let array = try? container.decode([JSONValue].self) {
      self = .array(array)
    } else if let object = try? container.decode([String: JSONValue].self) {
      self = .object(object)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "JSONValue: 无法识别的 JSON 值")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let bool): try container.encode(bool)
    case .int(let int): try container.encode(int)
    case .double(let double): try container.encode(double)
    case .string(let string): try container.encode(string)
    case .array(let array): try container.encode(array)
    case .object(let object): try container.encode(object)
    }
  }
}

// MARK: - 工具定义

/// 一件 DNS 操作工具的 MCP 标准描述。
/// 同一份定义同时驱动:① PodDockMCP 的 tools/list、tools/call;
/// ② App LLM 助手的 tool definitions(Anthropic / OpenAI 兼容)——单一契约源,永不漂移。
public struct MCPToolDefinition: Sendable, Equatable, Identifiable {
  public let name: String
  public let description: String
  public let inputSchema: JSONValue
  /// 只读工具(不改变任何状态)
  public let isReadOnly: Bool
  /// 破坏性工具(删除类;修改/启停不算)
  public let isDestructive: Bool

  public var id: String { name }

  public init(
    name: String, description: String, inputSchema: JSONValue,
    isReadOnly: Bool = false, isDestructive: Bool = false
  ) {
    self.name = name
    self.description = description
    self.inputSchema = inputSchema
    self.isReadOnly = isReadOnly
    self.isDestructive = isDestructive
  }
}

// MARK: - 目录

public enum MCPToolCatalog {
  private static func objectSchema(
    _ properties: [String: JSONValue],
    required: [String]
  ) -> JSONValue {
    .object([
      "type": .string("object"),
      "properties": .object(properties),
      "required": .array(required.map(JSONValue.string)),
      "additionalProperties": .bool(false),
    ])
  }

  private static func stringParam(_ description: String) -> JSONValue {
    .object(["type": .string("string"), "description": .string(description)])
  }

  private static func intParam(_ description: String) -> JSONValue {
    .object(["type": .string("integer"), "description": .string(description)])
  }

  private static func statusParam() -> JSONValue {
    .object([
      "type": .string("string"),
      "description": .string("目标状态"),
      "enum": .array([.string("enable"), .string("disable")]),
    ])
  }

  /// 全部工具。名称与 DNSPodClient 意图一一对应。
  public static let all: [MCPToolDefinition] = [
    MCPToolDefinition(
      name: "list_domains",
      description: "列出账户下全部域名(含状态、套餐等级、记录数)",
      inputSchema: objectSchema([:], required: []),
      isReadOnly: true),
    MCPToolDefinition(
      name: "create_domain",
      description: "添加一个新域名到账户",
      inputSchema: objectSchema(
        ["domain": stringParam("域名,如 example.com")],
        required: ["domain"])),
    MCPToolDefinition(
      name: "set_domain_status",
      description: "启用或暂停域名解析",
      inputSchema: objectSchema(
        [
          "domain_id": stringParam("域名 ID"),
          "status": statusParam(),
        ],
        required: ["domain_id", "status"])),
    MCPToolDefinition(
      name: "remove_domain",
      description: "从账户删除域名(危险操作,需用户确认)",
      inputSchema: objectSchema(
        ["domain_id": stringParam("域名 ID")],
        required: ["domain_id"]),
      isDestructive: true),
    MCPToolDefinition(
      name: "list_records",
      description: "列出指定域名的全部解析记录",
      inputSchema: objectSchema(
        ["domain_id": stringParam("域名 ID")],
        required: ["domain_id"]),
      isReadOnly: true),
    MCPToolDefinition(
      name: "record_options",
      description: "查询指定域名可用的记录类型与线路(填表单前先查这个)",
      inputSchema: objectSchema(
        [
          "domain_id": stringParam("域名 ID"),
          "grade": stringParam("域名套餐等级(来自 list_records 返回的 domain.grade)"),
        ],
        required: ["domain_id", "grade"]),
      isReadOnly: true),
    MCPToolDefinition(
      name: "create_record",
      description: "为域名新建一条解析记录",
      inputSchema: objectSchema(
        [
          "domain_id": stringParam("域名 ID"),
          "sub_domain": stringParam("主机记录,如 www;根域填 @;缺省 @"),
          "record_type": stringParam("记录类型,如 A/CNAME/MX/TXT(以 record_options 为准)"),
          "record_line": stringParam("线路,如 默认(以 record_options 为准)"),
          "value": stringParam("记录值(IP/目标/文本)"),
          "mx": intParam("MX 优先级,仅 MX 记录;缺省 10"),
          "ttl": intParam("TTL 秒数;缺省 600"),
          "remark": stringParam("备注,可选"),
        ],
        required: ["domain_id", "record_type", "record_line", "value"])),
    MCPToolDefinition(
      name: "update_record",
      description: "修改一条已存在的解析记录(整条覆盖,字段以当前值为基准)",
      inputSchema: objectSchema(
        [
          "domain_id": stringParam("域名 ID"),
          "record_id": stringParam("记录 ID"),
          "sub_domain": stringParam("主机记录"),
          "record_type": stringParam("记录类型"),
          "record_line": stringParam("线路"),
          "value": stringParam("记录值"),
          "mx": intParam("MX 优先级"),
          "ttl": intParam("TTL 秒数"),
          "remark": stringParam("新备注"),
        ],
        required: ["domain_id", "record_id", "sub_domain", "record_type", "record_line", "value"])),
    MCPToolDefinition(
      name: "set_record_status",
      description: "启用或暂停一条解析记录",
      inputSchema: objectSchema(
        [
          "domain_id": stringParam("域名 ID"),
          "record_id": stringParam("记录 ID"),
          "status": statusParam(),
        ],
        required: ["domain_id", "record_id", "status"])),
    MCPToolDefinition(
      name: "remove_record",
      description: "删除一条解析记录(危险操作,需用户确认)",
      inputSchema: objectSchema(
        [
          "domain_id": stringParam("域名 ID"),
          "record_id": stringParam("记录 ID"),
        ],
        required: ["domain_id", "record_id"]),
      isDestructive: true),
    MCPToolDefinition(
      name: "set_record_remark",
      description: "设置解析记录的备注",
      inputSchema: objectSchema(
        [
          "domain_id": stringParam("域名 ID"),
          "record_id": stringParam("记录 ID"),
          "remark": stringParam("备注文本,空串即清除"),
        ],
        required: ["domain_id", "record_id", "remark"])),
    MCPToolDefinition(
      name: "check_propagation",
      description: "通过 DoH 公网查询某主机名当前的实际解析结果,验证修改是否生效",
      inputSchema: objectSchema(
        [
          "name": stringParam("完整主机名,如 www.example.com"),
          "record_type": stringParam("记录类型,缺省 A"),
        ],
        required: ["name"]),
      isReadOnly: true),
  ]

  public static func tool(named name: String) -> MCPToolDefinition? {
    all.first { $0.name == name }
  }
}

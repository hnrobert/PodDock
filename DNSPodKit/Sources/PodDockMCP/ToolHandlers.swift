import Foundation
import MCP
import DNSPodKit

// MARK: - JSONValue → MCP Value

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
}

// MARK: - 工具调度

/// MCPToolCatalog 工具名 → DNSPodClient 调用 → 文本结果。
/// 服务双宿主共用(Linux executable / macOS App 内嵌),也可被 App 的 LLM 层复用。
enum MCPToolDispatch {
  enum DispatchError: Error, LocalizedError {
    case missingParameter(String)
    case notAuthenticated

    var errorDescription: String? {
      switch self {
      case .missingParameter(let name): "缺少参数:\(name)"
      case .notAuthenticated: "未登录:请先在本会话调用 dnspod_login 提供 DNSPod Token"
      }
    }
  }

  static func dispatch(
    name: String,
    arguments: [String: Value]?,
    client: DNSPodClient
  ) async throws -> String {
    let args = arguments ?? [:]
    func string(_ key: String) throws -> String {
      guard let value = args[key]?.stringValue, !value.isEmpty else {
        throw DispatchError.missingParameter(key)
      }
      return value
    }
    func optionalInt(_ key: String) -> Int? {
      args[key]?.intValue ?? args[key]?.doubleValue.flatMap(Int.init)
    }

    switch name {
    case "list_domains":
      let domains = try await client.listDomains()
      guard !domains.isEmpty else { return "账户下没有域名。" }
      return
        "共 \(domains.count) 个域名:\n"
        + domains.map { domain in
          "- \(domain.name)[\(domain.state.rawValue)] \(domain.recordCount) 条记录 · \(domain.grade) · id=\(domain.id.rawValue)"
        }
        .joined(separator: "\n")

    case "create_domain":
      let domainName = try string("domain")
      try await client.createDomain(name: domainName)
      return "已添加域名 \(domainName)。"

    case "set_domain_status":
      let domainID = try string("domain_id")
      let status = try string("status")
      let target: ToggleStatus = status == "enable" ? .enable : .disable
      try await client.setDomainStatus(id: DomainID(domainID), to: target)
      return "域名 \(domainID) 已\(target == .enable ? "启用" : "暂停")。"

    case "remove_domain":
      let domainID = try string("domain_id")
      try await client.removeDomain(id: DomainID(domainID))
      return "已删除域名 \(domainID)。"

    case "list_records":
      let domainID = try string("domain_id")
      let page = try await client.listRecords(domainID: DomainID(domainID))
      guard !page.records.isEmpty else { return "\(page.domain.name) 暂无解析记录。" }
      return
        "\(page.domain.name)(id=\(page.domain.id.rawValue), grade=\(page.domain.grade))共 \(page.records.count) 条:\n"
        + page.records.map { record in
          var line = "- [\(record.id.rawValue)] \(record.name) \(record.type) \(record.line) → \(record.value)(\(record.isEnabled ? "启用" : "暂停"), TTL \(record.ttl)"
          if record.type == "MX" { line += ", MX \(record.mx)" }
          if !record.remark.isEmpty { line += ",备注:\(record.remark)" }
          return line
        }
        .joined(separator: "\n")

    case "record_options":
      let domainID = try string("domain_id")
      let grade = try string("grade")
      let domain = DNSDomain(
        id: DomainID(domainID), name: "", grade: grade,
        state: .unknown, recordCount: 0, updatedOn: "")
      let options = try await client.recordOptions(for: domain)
      return "类型:\(options.types.joined(separator: ", "))\n线路:\(options.lines.joined(separator: ", "))"

    case "create_record":
      let domainID = try string("domain_id")
      let domain = DNSDomain(
        id: DomainID(domainID), name: domainID, grade: "", state: .unknown,
        recordCount: 0, updatedOn: "")
      let draft = RecordDraft(
        subDomain: args["sub_domain"]?.stringValue ?? "@",
        recordType: try string("record_type"),
        recordLine: try string("record_line"),
        value: try string("value"),
        mx: optionalInt("mx"),
        ttl: optionalInt("ttl"),
        remark: args["remark"]?.stringValue ?? "")
      let recordID = try await client.createRecord(draft, in: domain)
      return "已创建记录 \(recordID.rawValue)(\(draft.subDomain) \(draft.recordType) → \(draft.value))。"

    case "update_record":
      let domainID = try string("domain_id")
      let recordID = try string("record_id")
      let domain = DNSDomain(
        id: DomainID(domainID), name: domainID, grade: "", state: .unknown,
        recordCount: 0, updatedOn: "")
      let original = try await client.fetchRecord(id: RecordID(recordID), domainID: domain.id)
      let draft = RecordDraft(
        subDomain: try string("sub_domain"),
        recordType: try string("record_type"),
        recordLine: try string("record_line"),
        value: try string("value"),
        mx: optionalInt("mx"),
        ttl: optionalInt("ttl"),
        remark: args["remark"]?.stringValue ?? original.remark)
      try await client.updateRecord(id: RecordID(recordID), in: domain, from: original, to: draft)
      return "已修改记录 \(recordID)。"

    case "set_record_status":
      let domainID = try string("domain_id")
      let recordID = try string("record_id")
      let status = try string("status")
      let target: ToggleStatus = status == "enable" ? .enable : .disable
      try await client.setRecordStatus(id: RecordID(recordID), domainID: DomainID(domainID), to: target)
      return "记录 \(recordID) 已\(target == .enable ? "启用" : "暂停")。"

    case "remove_record":
      let domainID = try string("domain_id")
      let recordID = try string("record_id")
      try await client.removeRecord(id: RecordID(recordID), domainID: DomainID(domainID))
      return "已删除记录 \(recordID)。"

    case "set_record_remark":
      let domainID = try string("domain_id")
      let recordID = try string("record_id")
      let remark = args["remark"]?.stringValue ?? ""
      try await client.setRecordRemark(id: RecordID(recordID), domainID: DomainID(domainID), remark: remark)
      return remark.isEmpty ? "已清除备注。" : "备注已更新:\(remark)"

    case "check_propagation":
      let name = try string("name")
      let type = args["record_type"]?.stringValue ?? "A"
      let resolver = DoHResolver()
      let result = try await resolver.resolveWithFallback(name: name, recordType: type)
      let source: String
      switch result.source {
      case .doh(let provider): source = provider.displayName
      case .system: source = "系统解析回退"
      }
      guard !result.answers.isEmpty else { return "\(name)(\(type))当前无解析结果——可能尚未生效。" }
      return
        "\(name)(\(type))解析结果(来源:\(source)):\n"
        + result.answers.map { "- \($0.data)(TTL \($0.ttl))" }
        .joined(separator: "\n")

    default:
      throw DispatchError.missingParameter("未知工具 \(name)")
    }
  }
}

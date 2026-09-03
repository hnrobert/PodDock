import Foundation

// MARK: - Tool execution layer
//
// MCPToolCatalog tool name → DNSPodClient call → text result.
// Serves three hosts: the PodDockMCP server, the App LLM assistant, a future CLI — one impl, zero drift.

public enum ToolDispatch {
  public enum DispatchError: Error, LocalizedError, Sendable {
    case missingParameter(String)
    case unknownTool(String)

    public var errorDescription: String? {
      switch self {
      case .missingParameter(let name): "Missing parameter: \(name)"
      case .unknownTool(let name): "Unknown tool: \(name)"
      }
    }
  }

  public static func dispatch(
    name: String,
    arguments: [String: JSONValue],
    client: DNSPodClient
  ) async throws -> String {
    func string(_ key: String) throws -> String {
      guard let value = arguments[key]?.stringValue, !value.isEmpty else {
        throw DispatchError.missingParameter(key)
      }
      return value
    }
    func optionalInt(_ key: String) -> Int? {
      arguments[key]?.intValue
    }

    switch name {
    case "list_domains":
      let domains = try await client.listDomains()
      guard !domains.isEmpty else { return "No domains in this account." }
      return
        "\(domains.count) domains:\n"
        + domains.map { domain in
          "- \(domain.name)[\(domain.state.rawValue)] \(domain.recordCount) records · \(domain.grade) · id=\(domain.id.rawValue)"
        }
        .joined(separator: "\n")

    case "create_domain":
      let domainName = try string("domain")
      try await client.createDomain(name: domainName)
      return "Domain \(domainName) added."

    case "set_domain_status":
      let domainID = try string("domain_id")
      let status = try string("status")
      let target: ToggleStatus = status == "enable" ? .enable : .disable
      try await client.setDomainStatus(id: DomainID(domainID), to: target)
      return "Domain \(domainID) \(target == .enable ? "enabled" : "paused")."

    case "remove_domain":
      let domainID = try string("domain_id")
      try await client.removeDomain(id: DomainID(domainID))
      return "Domain \(domainID) removed."

    case "list_records":
      let domainID = try string("domain_id")
      let page = try await client.listRecords(domainID: DomainID(domainID))
      guard !page.records.isEmpty else { return "\(page.domain.name) has no records." }
      return
        "\(page.domain.name) (id=\(page.domain.id.rawValue), grade=\(page.domain.grade)), \(page.records.count) records:\n"
        + page.records.map { record in
          var line = "- [\(record.id.rawValue)] \(record.name) \(record.type) \(record.line) → \(record.value)(\(record.isEnabled ? "enabled" : "paused"), TTL \(record.ttl)"
          if record.type == "MX" { line += ", MX \(record.mx)" }
          if !record.remark.isEmpty { line += ", remark: \(record.remark)" }
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
      return "Types: \(options.types.joined(separator: ", "))\nLines: \(options.lines.joined(separator: ", "))"

    case "create_record":
      let domainID = try string("domain_id")
      let domain = DNSDomain(
        id: DomainID(domainID), name: domainID, grade: "", state: .unknown,
        recordCount: 0, updatedOn: "")
      let draft = RecordDraft(
        subDomain: arguments["sub_domain"]?.stringValue ?? "@",
        recordType: try string("record_type"),
        recordLine: try string("record_line"),
        value: try string("value"),
        mx: optionalInt("mx"),
        ttl: optionalInt("ttl"),
        remark: arguments["remark"]?.stringValue ?? "",
        weight: optionalInt("weight"))
      let recordID = try await client.createRecord(draft, in: domain)
      return "Record \(recordID.rawValue) created (\(draft.subDomain) \(draft.recordType) → \(draft.value))."

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
        remark: arguments["remark"]?.stringValue ?? original.remark,
        weight: optionalInt("weight"))
      try await client.updateRecord(id: RecordID(recordID), in: domain, from: original, to: draft)
      return "Record \(recordID) updated."

    case "set_record_status":
      let domainID = try string("domain_id")
      let recordID = try string("record_id")
      let status = try string("status")
      let target: ToggleStatus = status == "enable" ? .enable : .disable
      try await client.setRecordStatus(id: RecordID(recordID), domainID: DomainID(domainID), to: target)
      return "Record \(recordID) \(target == .enable ? "enabled" : "paused")."

    case "remove_record":
      let domainID = try string("domain_id")
      let recordID = try string("record_id")
      try await client.removeRecord(id: RecordID(recordID), domainID: DomainID(domainID))
      return "Record \(recordID) removed."

    case "set_record_remark":
      let domainID = try string("domain_id")
      let recordID = try string("record_id")
      let remark = arguments["remark"]?.stringValue ?? ""
      try await client.setRecordRemark(id: RecordID(recordID), domainID: DomainID(domainID), remark: remark)
      return remark.isEmpty ? "Remark cleared." : "Remark updated: \(remark)"

    case "check_propagation":
      let name = try string("name")
      let type = arguments["record_type"]?.stringValue ?? "A"
      let resolver = DoHResolver()
      let result = try await resolver.resolveWithFallback(name: name, recordType: type)
      let source: String
      switch result.source {
      case .doh(let provider): source = provider.displayName
      case .system: source = "system resolver fallback"
      }
      guard !result.answers.isEmpty else { return "\(name) (\(type)) has no answers — the change may not be live yet." }
      return
        "\(name) (\(type)) resolution (source: \(source)):\n"
        + result.answers.map { "- \($0.data)(TTL \($0.ttl))" }
        .joined(separator: "\n")

    default:
      throw DispatchError.unknownTool(name)
    }
  }
}

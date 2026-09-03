import Foundation

// MARK: - Legacy API response DTOs
//
// Shapes from the reference app.py and docs.dnspod.cn samples; numeric fields all Flex-tolerant,
// Real fixtures to be captured with a live token in M1 (Fixtures/*.json).

struct LegacyStatusDTO: Codable {
  let code: FlexInt
  let message: String
}

struct StatusOnlyResponse: Codable {
  let status: LegacyStatusDTO
}

struct LegacyDomainDTO: Codable {
  let id: FlexString
  let name: String?
  let grade: String?
  let status: FlexString?
  let records: FlexInt?
  let updatedOn: FlexString?

  enum CodingKeys: String, CodingKey {
    case id, name, grade, status, records
    case updatedOn = "updated_on"
  }

  var toDomain: DNSDomain? {
    guard let name else { return nil }
    return DNSDomain(
      id: DomainID(rawValue: id.value),
      name: name,
      grade: grade ?? "",
      state: DomainState.parse(status?.value ?? ""),
      recordCount: records?.value ?? 0,
      updatedOn: updatedOn?.value ?? ""
    )
  }

  var toSummary: DomainSummary? {
    guard let name else { return nil }
    return DomainSummary(id: DomainID(rawValue: id.value), name: name, grade: grade ?? "")
  }
}

struct DomainListResponse: Codable {
  let status: LegacyStatusDTO
  let domains: [LegacyDomainDTO]?
}

struct RecordListResponse: Codable {
  let status: LegacyStatusDTO
  let domain: LegacyDomainDTO?
  let records: [LegacyRecordDTO]?
}

struct RecordInfoResponse: Codable {
  let status: LegacyStatusDTO
  let record: LegacyRecordDTO?
}

struct RecordRefDTO: Codable {
  let id: FlexString?
}

struct RecordCreateResponse: Codable {
  let status: LegacyStatusDTO
  let record: RecordRefDTO?
}

struct RecordTypesResponse: Codable {
  let status: LegacyStatusDTO
  let types: [String]?
}

struct RecordLinesResponse: Codable {
  let status: LegacyStatusDTO
  let lines: [String]?
}

/// Record.List and Record.Info use different keys (`type`/`line` vs `record_type`/`record_line`);
/// Decodes both shapes into one DNSRecord.
struct LegacyRecordDTO: Codable {
  let id: FlexString
  let name: String?
  let subDomain: String?
  let type: String?
  let recordType: String?
  let line: String?
  let recordLine: String?
  let value: FlexString?
  let enabled: FlexBool?
  let mx: FlexInt?
  let ttl: FlexInt?
  let remark: String?
  /// Load-balancing weight, nullable in Record.List responses (undocumented in the field table)
  let weight: FlexInt?

  enum CodingKeys: String, CodingKey {
    case id, name, type, line, value, enabled, mx, ttl, remark, weight
    case subDomain = "sub_domain"
    case recordType = "record_type"
    case recordLine = "record_line"
  }

  var toRecord: DNSRecord {
    DNSRecord(
      id: RecordID(rawValue: id.value),
      name: name ?? subDomain ?? "@",
      type: type ?? recordType ?? "",
      line: line ?? recordLine ?? "默认",
      value: value?.value ?? "",
      isEnabled: enabled?.value ?? false,
      mx: mx?.value ?? 10,
      ttl: ttl?.value ?? 600,
      remark: remark ?? "",
      weight: weight?.value
    )
  }
}

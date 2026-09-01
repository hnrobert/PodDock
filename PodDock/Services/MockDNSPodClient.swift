import Foundation
import DNSPodKit

#if DEBUG
  /// Deterministic in-memory mock shared by SwiftUI previews and future XCUITests (--uitest-mock).
  /// create/modify/status/remark all mutate in-memory data; supports failure injection.
  @MainActor
  final class MockDNSPodClient: DNSPodClient {
    nonisolated var capabilities: Set<DNSPodCapability> { [] }

    /// When true, the next call throws an auth failure (UI-test scenario: --uitest-scenario auth_failure)
    var failNextCall = false

    private(set) var domains: [DNSDomain]
    private var recordsByDomain: [String: [DNSRecord]]

    init() {
      let example = DNSDomain(
        id: DomainID("900001"), name: "example.com", grade: "DP_Free",
        state: .enable, recordCount: 3, updatedOn: "2026-08-30 12:00:00")
      let demo = DNSDomain(
        id: DomainID("900002"), name: "demo.example.net", grade: "DP_Plus",
        state: .pause, recordCount: 1, updatedOn: "2026-08-29 09:00:00")
      domains = [example, demo]
      recordsByDomain = [
        "900001": [
          DNSRecord(
            id: RecordID("910001"), name: "www", type: "A", line: "默认", value: "203.0.113.10",
            isEnabled: true, mx: 0, ttl: 600, remark: "主站"),
          DNSRecord(
            id: RecordID("910002"), name: "@", type: "MX", line: "默认", value: "mx.example.com.",
            isEnabled: false, mx: 10, ttl: 600, remark: "mail"),
          DNSRecord(
            id: RecordID("910003"), name: "api", type: "CNAME", line: "联通", value: "cdn.example.net",
            isEnabled: true, mx: 0, ttl: 120, remark: ""),
        ],
        "900002": [
          DNSRecord(
            id: RecordID("910004"), name: "www", type: "A", line: "默认", value: "198.51.100.7",
            isEnabled: true, mx: 0, ttl: 600, remark: "")
        ],
      ]
    }

    private func maybeFail() throws {
      if failNextCall {
        failNextCall = false
        throw DNSPodError.api(code: 6, message: "模拟认证失败")
      }
    }

    func validateCredentials() async throws {
      try maybeFail()
    }

    func listDomains() async throws -> [DNSDomain] {
      try maybeFail()
      return domains
    }

    func createDomain(name: String) async throws {
      try maybeFail()
      domains.append(
        DNSDomain(
          id: DomainID(String(900000 + domains.count + 1)), name: name, grade: "DP_Free",
          state: .enable, recordCount: 0, updatedOn: ""))
    }

    func setDomainStatus(id: DomainID, to status: ToggleStatus) async throws {
      try maybeFail()
      domains = domains.map { domain in
        guard domain.id == id else { return domain }
        return DNSDomain(
          id: domain.id, name: domain.name, grade: domain.grade,
          state: status == .enable ? .enable : .pause,
          recordCount: domain.recordCount, updatedOn: domain.updatedOn)
      }
    }

    func removeDomain(id: DomainID) async throws {
      try maybeFail()
      domains.removeAll { $0.id == id }
      recordsByDomain[id.rawValue] = nil
    }

    func listRecords(domainID: DomainID) async throws -> RecordListPage {
      try maybeFail()
      let records = recordsByDomain[domainID.rawValue] ?? []
      guard let domain = domains.first(where: { $0.id == domainID }) else {
        throw DNSPodError.invalidResponse("mock: 未知域名 \(domainID)")
      }
      return RecordListPage(
        records: records,
        domain: DomainSummary(id: domain.id, name: domain.name, grade: domain.grade))
    }

    func fetchRecord(id: RecordID, domainID: DomainID) async throws -> DNSRecord {
      try maybeFail()
      guard let record = recordsByDomain[domainID.rawValue]?.first(where: { $0.id == id }) else {
        throw DNSPodError.invalidResponse("mock: 未知记录 \(id)")
      }
      return record
    }

    func recordOptions(for domain: DNSDomain) async throws -> RecordOptions {
      try maybeFail()
      return RecordOptions(
        types: ["A", "CNAME", "MX", "TXT", "AAAA", "NS", "SRV", "CAA"],
        lines: ["默认", "电信", "联通", "移动"])
    }

    func createRecord(_ draft: RecordDraft, in domain: DNSDomain) async throws -> RecordID {
      try maybeFail()
      let record = DNSRecord(
        id: RecordID("9" + String(Int.random(in: 100000...999999))),
        name: draft.subDomain, type: draft.recordType, line: draft.recordLine,
        value: draft.value, isEnabled: true, mx: draft.mx, ttl: draft.ttl, remark: draft.remark)
      recordsByDomain[domain.id.rawValue, default: []].append(record)
      return record.id
    }

    func updateRecord(
      id: RecordID, in domain: DNSDomain, from original: DNSRecord, to draft: RecordDraft
    ) async throws {
      try maybeFail()
      let updated = DNSRecord(
        id: id, name: draft.subDomain, type: draft.recordType, line: draft.recordLine,
        value: draft.value, isEnabled: original.isEnabled, mx: draft.mx, ttl: draft.ttl,
        remark: draft.remark)
      recordsByDomain[domain.id.rawValue] = (recordsByDomain[domain.id.rawValue] ?? []).map {
        $0.id == id ? updated : $0
      }
    }

    func setRecordStatus(id: RecordID, domainID: DomainID, to status: ToggleStatus) async throws {
      try maybeFail()
      recordsByDomain[domainID.rawValue] = (recordsByDomain[domainID.rawValue] ?? []).map {
        record in
        guard record.id == id else { return record }
        return DNSRecord(
          id: record.id, name: record.name, type: record.type, line: record.line,
          value: record.value, isEnabled: status == .enable, mx: record.mx, ttl: record.ttl,
          remark: record.remark)
      }
    }

    func removeRecord(id: RecordID, domainID: DomainID) async throws {
      try maybeFail()
      recordsByDomain[domainID.rawValue] = (recordsByDomain[domainID.rawValue] ?? []).filter {
        $0.id != id
      }
    }

    func setRecordRemark(id: RecordID, domainID: DomainID, remark: String) async throws {
      try maybeFail()
      recordsByDomain[domainID.rawValue] = (recordsByDomain[domainID.rawValue] ?? []).map {
        record in
        guard record.id == id else { return record }
        return DNSRecord(
          id: record.id, name: record.name, type: record.type, line: record.line,
          value: record.value, isEnabled: record.isEnabled, mx: record.mx, ttl: record.ttl,
          remark: remark)
      }
    }
  }
#endif

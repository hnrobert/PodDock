import Foundation

/// Tencent Cloud API 3.0 impl (dnspod.tencentcloudapi.com + TC3-HMAC-SHA256).
///
/// Upgraded to a minimal impl in M5 (validateCredentials first, proving the abstraction);
/// Placeholder: everything throws `notImplemented`. Capabilities preview the differences:
/// inline remark on modify / server batch / strict pagination.
public struct TencentCloudClient: DNSPodClient {
  public var capabilities: Set<DNSPodCapability> {
    [.inlineRemark, .batchStatus, .pagination]
  }

  public init() {}

  public func validateCredentials() async throws {
    throw DNSPodError.notImplemented("TencentCloudClient 计划于 M5 提供")
  }

  public func listDomains() async throws -> [DNSDomain] {
    throw DNSPodError.notImplemented("TencentCloudClient 计划于 M5 提供")
  }

  public func createDomain(name: String) async throws {
    throw DNSPodError.notImplemented("TencentCloudClient 计划于 M5 提供")
  }

  public func setDomainStatus(id: DomainID, to status: ToggleStatus) async throws {
    throw DNSPodError.notImplemented("TencentCloudClient 计划于 M5 提供")
  }

  public func removeDomain(id: DomainID) async throws {
    throw DNSPodError.notImplemented("TencentCloudClient 计划于 M5 提供")
  }

  public func listRecords(domainID: DomainID) async throws -> RecordListPage {
    throw DNSPodError.notImplemented("TencentCloudClient 计划于 M5 提供")
  }

  public func fetchRecord(id: RecordID, domainID: DomainID) async throws -> DNSRecord {
    throw DNSPodError.notImplemented("TencentCloudClient 计划于 M5 提供")
  }

  public func recordOptions(for domain: DNSDomain) async throws -> RecordOptions {
    throw DNSPodError.notImplemented("TencentCloudClient 计划于 M5 提供")
  }

  public func createRecord(_ draft: RecordDraft, in domain: DNSDomain) async throws -> RecordID {
    throw DNSPodError.notImplemented("TencentCloudClient 计划于 M5 提供")
  }

  public func updateRecord(
    id: RecordID, in domain: DNSDomain, from original: DNSRecord, to draft: RecordDraft
  ) async throws {
    throw DNSPodError.notImplemented("TencentCloudClient 计划于 M5 提供")
  }

  public func setRecordStatus(id: RecordID, domainID: DomainID, to status: ToggleStatus) async throws {
    throw DNSPodError.notImplemented("TencentCloudClient 计划于 M5 提供")
  }

  public func removeRecord(id: RecordID, domainID: DomainID) async throws {
    throw DNSPodError.notImplemented("TencentCloudClient 计划于 M5 提供")
  }

  public func setRecordRemark(id: RecordID, domainID: DomainID, remark: String) async throws {
    throw DNSPodError.notImplemented("TencentCloudClient 计划于 M5 提供")
  }
}

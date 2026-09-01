import Foundation

/// Capability flags — API-generational differences made explicit so the App can branch on them.
public struct DNSPodCapability: Sendable, Hashable {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  /// Tencent Cloud API 3.0 inlines the remark on modify; otherwise a separate Remark call is needed
  public static let inlineRemark = DNSPodCapability(rawValue: "inlineRemark")
  /// Server-side batch endpoint exists
  public static let batchStatus = DNSPodCapability(rawValue: "batchStatus")
  /// Server list endpoints paginate
  public static let pagination = DNSPodCapability(rawValue: "pagination")
}

/// Intent-level DNSPodClient protocol — business semantics, not endpoint mirroring.
///
/// Compositional differences between the two impls (legacy / Tencent Cloud 3.0) stay inside them:
/// - `updateRecord(from:to:)`: LegacyClient decides "remark changed → follow-up Record.Remark",
///   TC3 inlines it;
/// - `RecordDraft` fills its `@`/MX=10/TTL=600 defaults at construction;
/// - Partial-failure contract: op ok but remark failed → `DNSPodError.remarkFailed` (non-atomic),
///   the UI surfaces it as a non-blocking notice and refreshes.
public protocol DNSPodClient: Sendable {
  var capabilities: Set<DNSPodCapability> { get }

  /// Validate credentials. Legacy: `listDomains()` (error_on_empty=no returns code 1 even when empty)
  func validateCredentials() async throws

  func listDomains() async throws -> [DNSDomain]
  func createDomain(name: String) async throws
  func setDomainStatus(id: DomainID, to status: ToggleStatus) async throws
  func removeDomain(id: DomainID) async throws

  func listRecords(domainID: DomainID) async throws -> RecordListPage
  func fetchRecord(id: RecordID, domainID: DomainID) async throws -> DNSRecord
  func recordOptions(for domain: DNSDomain) async throws -> RecordOptions
  func createRecord(_ draft: RecordDraft, in domain: DNSDomain) async throws -> RecordID
  func updateRecord(id: RecordID, in domain: DNSDomain, from original: DNSRecord, to draft: RecordDraft) async throws
  func setRecordStatus(id: RecordID, domainID: DomainID, to status: ToggleStatus) async throws
  func removeRecord(id: RecordID, domainID: DomainID) async throws
  func setRecordRemark(id: RecordID, domainID: DomainID, remark: String) async throws
}

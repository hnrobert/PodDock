import Foundation

/// DNSPod 客户端能力声明——两代 API 的行为差异显式化,App 层可按能力分支。
public struct DNSPodCapability: Sendable, Hashable {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  /// 修改记录时备注直接内联(腾讯云 API 3.0);否则需单独补调 Remark
  public static let inlineRemark = DNSPodCapability(rawValue: "inlineRemark")
  /// 服务端批量端点存在
  public static let batchStatus = DNSPodCapability(rawValue: "batchStatus")
  /// 列表接口强分页
  public static let pagination = DNSPodCapability(rawValue: "pagination")
}

/// 意图级 DNSPod 客户端协议——按业务语义而非端点镜像定义。
///
/// 两个实现(传统 API / 腾讯云 API 3.0)的组合差异全部留在实现内部:
/// - `updateRecord(from:to:)`:LegacyClient 自己决定"备注变化才补调 Record.Remark",
///   TC3 直接内联;
/// - `RecordDraft` 的 `@`/MX=10/TTL=600 默认值在构造层补齐;
/// - 部分失败契约:主操作成功但备注失败时抛 `DNSPodError.remarkFailed`(非原子),
///   UI 按非阻塞提示处理并刷新列表。
public protocol DNSPodClient: Sendable {
  var capabilities: Set<DNSPodCapability> { get }

  /// 校验凭据。Legacy 实现 = `listDomains()`(error_on_empty=no,空账户也返回 code 1)
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

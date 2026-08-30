import Foundation
import DNSPodKit
import Observation

/// 记录列表模型:加载/筛选/排序/启停/备注快编/批量(顺序 + 节流)。
@MainActor
@Observable
final class RecordListModel {
  enum SortOrder: String, CaseIterable, Identifiable {
    case byName = "按名称"
    case byType = "按类型"
    case byTTL = "按 TTL"
    var id: String { rawValue }
  }

  private weak var environment: AppEnvironment?
  private(set) var domain: DNSDomain?

  private(set) var records: [DNSRecord] = []
  private(set) var isLoading = false
  var errorMessage: String?
  var latestMessage: String?

  var searchText = ""
  var typeFilter: String?
  var sortOrder: SortOrder = .byName

  /// 批量执行进度
  private(set) var isBatchRunning = false

  func attach(environment: AppEnvironment, domain: DNSDomain) {
    self.environment = environment
    self.domain = domain
  }

  var availableTypes: [String] {
    var seen = Set<String>()
    return records.map(\.type).filter { seen.insert($0).inserted }.sorted()
  }

  var filteredRecords: [DNSRecord] {
    var result = records
    let keyword = searchText.trimmingCharacters(in: .whitespaces).lowercased()
    if !keyword.isEmpty {
      result = result.filter {
        $0.name.lowercased().contains(keyword)
          || $0.value.lowercased().contains(keyword)
          || $0.remark.lowercased().contains(keyword)
      }
    }
    if let typeFilter {
      result = result.filter { $0.type == typeFilter }
    }
    switch sortOrder {
    case .byName: result.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    case .byType: result.sort { ($0.type, $0.name) < ($1.type, $1.name) }
    case .byTTL: result.sort { ($0.ttl, $0.name) < ($1.ttl, $1.name) }
    }
    return result
  }

  func load() async {
    guard let client = environment?.client, let domain, !isLoading else { return }
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      let page = try await client.listRecords(domainID: domain.id)
      records = page.records
    } catch let error as DNSPodError {
      if error.isAuthenticationFailure, let environment {
        await environment.handleAuthenticationFailure()
      }
      errorMessage = error.localizedDescription
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func toggle(_ record: DNSRecord) async {
    guard let client = environment?.client, let domain else { return }
    let target: ToggleStatus = record.isEnabled ? .disable : .enable
    do {
      try await client.setRecordStatus(id: record.id, domainID: domain.id, to: target)
      await load()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func remove(_ record: DNSRecord) async {
    guard let client = environment?.client, let domain else { return }
    do {
      try await client.removeRecord(id: record.id, domainID: domain.id)
      records.removeAll { $0.id == record.id }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func setRemark(_ remark: String, for record: DNSRecord) async {
    guard let client = environment?.client, let domain else { return }
    do {
      try await client.setRecordRemark(id: record.id, domainID: domain.id, remark: remark)
      await load()
      latestMessage = "备注已更新"
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// 批量操作:顺序执行 + 0.3s 节流,失败逐条汇总(传统 API 无批量端点)
  func batch(_ records: [DNSRecord], action: BatchAction) async {
    guard let client = environment?.client, let domain, !isBatchRunning else { return }
    isBatchRunning = true
    defer { isBatchRunning = false }

    var failures: [String] = []
    for (index, record) in records.enumerated() {
      if index > 0 {
        try? await Task.sleep(for: .milliseconds(300))
      }
      do {
        switch action {
        case .enable:
          try await client.setRecordStatus(id: record.id, domainID: domain.id, to: .enable)
        case .disable:
          try await client.setRecordStatus(id: record.id, domainID: domain.id, to: .disable)
        case .remove:
          try await client.removeRecord(id: record.id, domainID: domain.id)
        }
      } catch {
        failures.append("\(record.name): \(error.localizedDescription)")
      }
    }
    await load()
    latestMessage =
      failures.isEmpty
      ? "批量操作完成(\(records.count) 条)"
      : "完成 \(records.count - failures.count)/\(records.count),失败:\(failures.joined(separator: ";"))"
  }

  enum BatchAction {
    case enable
    case disable
    case remove
  }
}

import Foundation
import DNSPodKit
import Observation

/// Record list model: load/filter/sort/toggle/quick remark/batch (sequential + throttled).
@MainActor
@Observable
final class RecordListModel {
  enum SortOrder: String, CaseIterable, Identifiable {
    case byName
    case byType
    case byTTL
    case byAdded
    case byWeight

    var id: String { rawValue }

    var displayName: String {
      switch self {
      case .byName: String(localized: "By Name")
      case .byType: String(localized: "By Type")
      case .byTTL: String(localized: "By TTL")
      case .byAdded: String(localized: "By Added Time")
      case .byWeight: String(localized: "By Weight")
      }
    }
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

  /// Batch progress
  private(set) var isBatchRunning = false

  /// Last-loaded records per domain — switching domains shows the cache
  /// instantly (stale-while-revalidate) while load() refreshes in background
  private var cache: [DomainID: [DNSRecord]] = [:]
  /// Increments per load(); completions from superseded loads are dropped.
  /// Without it, the `!isLoading` race between a cancelled task's cleanup and
  /// the next task's start could leave a domain switch never loading.
  private var loadGeneration = 0

  func attach(environment: AppEnvironment, domain: DNSDomain) {
    self.environment = environment
    if self.domain?.id != domain.id {
      records = cache[domain.id] ?? []
      errorMessage = nil
    }
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
    // DNSPod assigns record ids sequentially, so numeric id order ≈ creation order
    // (Record.List exposes no created_on; only updated_on)
    case .byAdded: result.sort { (UInt64($0.id.rawValue) ?? 0, $0.name) < (UInt64($1.id.rawValue) ?? 0, $1.name) }
    // Higher weight first; unset (nil) weights sink to the bottom
    case .byWeight: result.sort { lhs, rhs in
      switch (lhs.weight, rhs.weight) {
      case let (l?, r?): l > r || (l == r && lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending)
      case (_?, nil): true
      case (nil, _?): false
      case (nil, nil): lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
      }
    }
    }
    return result
  }

  func load() async {
    guard let client = environment?.client, let domain else { return }
    loadGeneration += 1
    let generation = loadGeneration
    isLoading = true
    errorMessage = nil
    defer { if generation == loadGeneration { isLoading = false } }
    do {
      let page = try await client.listRecords(domainID: domain.id)
      guard generation == loadGeneration else { return }
      records = page.records
      cache[domain.id] = page.records
    } catch is CancellationError {
      // Domain switched mid-flight; the newer load owns the UI now
    } catch let error as DNSPodError {
      guard generation == loadGeneration else { return }
      if error.isAuthenticationFailure, let environment {
        await environment.handleAuthenticationFailure()
      }
      errorMessage = describeError(error)
    } catch {
      guard generation == loadGeneration else { return }
      errorMessage = describeError(error)
    }
  }

  func toggle(_ record: DNSRecord) async {
    guard let client = environment?.client, let domain else { return }
    let target: ToggleStatus = record.isEnabled ? .disable : .enable
    do {
      try await client.setRecordStatus(id: record.id, domainID: domain.id, to: target)
      await load()
    } catch {
      errorMessage = describeError(error)
    }
  }

  func remove(_ record: DNSRecord) async {
    guard let client = environment?.client, let domain else { return }
    do {
      try await client.removeRecord(id: record.id, domainID: domain.id)
      records.removeAll { $0.id == record.id }
      if var cached = cache[domain.id] {
        cached.removeAll { $0.id == record.id }
        cache[domain.id] = cached
      }
    } catch {
      errorMessage = describeError(error)
    }
  }

  func setRemark(_ remark: String, for record: DNSRecord) async {
    guard let client = environment?.client, let domain else { return }
    do {
      try await client.setRecordRemark(id: record.id, domainID: domain.id, remark: remark)
      await load()
      latestMessage = String(localized: "Remark updated")
    } catch {
      errorMessage = describeError(error)
    }
  }

  /// Batch: sequential with a 0.3s throttle; failures reported per item (the legacy API has no batch endpoint)
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
        failures.append("\(record.name): \(describeError(error))")
      }
    }
    await load()
    latestMessage =
      failures.isEmpty
      ? String(localized: "Batch complete (\(records.count) items)")
      : String(
        format: String(localized: "Batch finished %1$lld/%2$lld, failed: %3$@"),
        records.count - failures.count, records.count, failures.joined(separator: "; "))
  }

  enum BatchAction {
    case enable
    case disable
    case remove
  }
}

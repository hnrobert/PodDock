import Foundation

/// 记录表单元数据缓存(传统 API 的行为知识,留在 Kit 内)。
///
/// `Record.Type` 按 grade 缓存、`Record.Line` 按 domain_id 缓存——
/// 对齐参考实现的 session key 语义(`type_<grade>` / `line_<domain_id>`)。
/// 进程级缓存,`reset()` 用于强制刷新。
public actor RecordOptionsProvider {
  private var typesByGrade: [String: [String]] = [:]
  private var linesByDomain: [String: [String]] = [:]
  private let fetchTypes: @Sendable (String) async throws -> [String]
  private let fetchLines: @Sendable (DomainID, String) async throws -> [String]

  public init(
    fetchTypes: @escaping @Sendable (String) async throws -> [String],
    fetchLines: @escaping @Sendable (DomainID, String) async throws -> [String]
  ) {
    self.fetchTypes = fetchTypes
    self.fetchLines = fetchLines
  }

  public func options(for domain: DNSDomain) async throws -> RecordOptions {
    let types: [String]
    if let cached = typesByGrade[domain.grade] {
      types = cached
    } else {
      types = try await fetchTypes(domain.grade)
      typesByGrade[domain.grade] = types
    }

    let lines: [String]
    let domainKey = domain.id.rawValue
    if let cached = linesByDomain[domainKey] {
      lines = cached
    } else {
      lines = try await fetchLines(domain.id, domain.grade)
      linesByDomain[domainKey] = lines
    }

    return RecordOptions(types: types, lines: lines)
  }

  public func reset() {
    typesByGrade.removeAll()
    linesByDomain.removeAll()
  }
}

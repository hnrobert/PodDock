import Foundation

/// Form-metadata cache (legacy-API knowledge kept inside the Kit).
///
/// `Record.Type` cached by grade, `Record.Line` by domain_id —
/// Mirrors the reference session-key semantics (`type_<grade>` / `line_<domain_id>`).
/// Process-lifetime cache; `reset()` forces a refetch.
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

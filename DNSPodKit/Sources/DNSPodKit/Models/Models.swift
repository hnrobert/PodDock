import Foundation

// MARK: - Strongly-typed IDs

/// Domain ID. DNSPod returns numbers as strings; String avoids Int overflow and brittle decoding.
public struct DomainID: Hashable, Sendable, Codable, CustomStringConvertible {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(_ raw: String) { self.rawValue = raw }
  public var description: String { rawValue }
}

/// Record ID.
public struct RecordID: Hashable, Sendable, Codable, CustomStringConvertible {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(_ raw: String) { self.rawValue = raw }
  public var description: String { rawValue }
}

// MARK: - Status

/// Toggle target (wire values enable/disable).
public enum ToggleStatus: String, Sendable {
  case enable
  case disable
}

/// Domain display state (wire: enable/pause/spam/lock; spam/lock not toggleable).
public enum DomainState: String, Sendable {
  case enable
  case pause
  case spam
  case lock
  case unknown

  /// Tolerant parse of unknown strings (the reference `grade_list[...]` KeyErrors here — we must not crash)
  public static func parse(_ raw: String) -> DomainState {
    DomainState(rawValue: raw) ?? .unknown
  }
}

// MARK: - Domains

public struct DNSDomain: Hashable, Sendable, Identifiable {
  public let id: DomainID
  public let name: String
  /// Raw plan grade (e.g. DP_Free); unknown values pass through for tolerant display
  public let grade: String
  public let state: DomainState
  public let recordCount: Int
  /// Raw server timestamp (not ISO8601; display verbatim or format at the view layer)
  public let updatedOn: String

  public init(
    id: DomainID, name: String, grade: String, state: DomainState,
    recordCount: Int, updatedOn: String
  ) {
    self.id = id
    self.name = name
    self.grade = grade
    self.state = state
    self.recordCount = recordCount
    self.updatedOn = updatedOn
  }

  public static func == (lhs: DNSDomain, rhs: DNSDomain) -> Bool { lhs.id == rhs.id }
  public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Domain summary riding on the record list — `grade` is the authoritative form-metadata source.
public struct DomainSummary: Hashable, Sendable {
  public let id: DomainID
  public let name: String
  public let grade: String

  public init(id: DomainID, name: String, grade: String) {
    self.id = id
    self.name = name
    self.grade = grade
  }
}

// MARK: - Records

public struct DNSRecord: Hashable, Sendable, Identifiable {
  public let id: RecordID
  /// Host record; `@` means the zone apex
  public let name: String
  public let type: String
  public let line: String
  public let value: String
  public let isEnabled: Bool
  public let mx: Int
  public let ttl: Int
  public let remark: String
  /// Load-balancing weight (0–100, same name+type records share traffic by it);
  /// nil = absent/unset (the field is nullable in Record.List responses)
  public let weight: Int?

  public init(
    id: RecordID, name: String, type: String, line: String, value: String,
    isEnabled: Bool, mx: Int, ttl: Int, remark: String, weight: Int? = nil
  ) {
    self.id = id
    self.name = name
    self.type = type
    self.line = line
    self.value = value
    self.isEnabled = isEnabled
    self.mx = mx
    self.ttl = ttl
    self.remark = remark
    self.weight = weight
  }

  public static func == (lhs: DNSRecord, rhs: DNSRecord) -> Bool { lhs.id == rhs.id }
  public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Record draft (form layer). Defaults filled here: `@` / MX=10 / TTL=600, matching the reference.
public struct RecordDraft: Hashable, Sendable {
  public var subDomain: String
  public var recordType: String
  public var recordLine: String
  public var value: String
  public var mx: Int
  public var ttl: Int
  public var remark: String
  /// Load-balancing weight (0–100). nil = don't touch the wire field
  /// (create: server default; modify: keep the existing value)
  public var weight: Int?

  public init(
    subDomain: String = "@",
    recordType: String = "A",
    recordLine: String = "默认",
    value: String,
    mx: Int? = nil,
    ttl: Int? = nil,
    remark: String = "",
    weight: Int? = nil
  ) {
    self.subDomain = subDomain.isEmpty ? "@" : subDomain
    self.recordType = recordType
    self.recordLine = recordLine
    self.value = value
    // MX defaults to 10, TTL to 600 (only when the caller omits them; matches the reference app)
    self.mx = mx ?? 10
    self.ttl = ttl ?? 600
    self.remark = remark
    self.weight = weight
  }
}

/// Record list page — paged from day one so TC3 pagination drops in without caller changes.
public struct RecordListPage: Sendable {
  public let records: [DNSRecord]
  public let domain: DomainSummary
  /// Legacy fetches everything at once, always false; paged impls fill the real value
  public let hasMore: Bool

  public init(records: [DNSRecord], domain: DomainSummary, hasMore: Bool = false) {
    self.records = records
    self.domain = domain
    self.hasMore = hasMore
  }
}

/// Form metadata: available types + lines.
public struct RecordOptions: Hashable, Sendable {
  public let types: [String]
  public let lines: [String]

  public init(types: [String], lines: [String]) {
    self.types = types
    self.lines = lines
  }
}

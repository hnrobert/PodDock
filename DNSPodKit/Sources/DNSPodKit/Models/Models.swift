import Foundation

// MARK: - 强类型 ID

/// 域名 ID。DNSPod 把数字当字符串返回,统一以 String 承载,防 Int 溢出与解码脆裂。
public struct DomainID: Hashable, Sendable, Codable, CustomStringConvertible {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(_ raw: String) { self.rawValue = raw }
  public var description: String { rawValue }
}

/// 记录 ID。
public struct RecordID: Hashable, Sendable, Codable, CustomStringConvertible {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(_ raw: String) { self.rawValue = raw }
  public var description: String { rawValue }
}

// MARK: - 状态

/// 启停切换的目标状态(线格式 enable/disable)。
public enum ToggleStatus: String, Sendable {
  case enable
  case disable
}

/// 域名展示状态(线格式 enable/pause/spam/lock;spam/lock 不可切换)。
public enum DomainState: String, Sendable {
  case enable
  case pause
  case spam
  case lock
  case unknown

  /// 未知字符串容错解析(参考实现 `grade_list[domain['grade']]` 会直接 KeyError,这里必须不崩)
  public static func parse(_ raw: String) -> DomainState {
    DomainState(rawValue: raw) ?? .unknown
  }
}

// MARK: - 域名

public struct DNSDomain: Hashable, Sendable, Identifiable {
  public let id: DomainID
  public let name: String
  /// 套餐等级原始字符串(如 DP_Free);未知值原样保留,App 层容错展示
  public let grade: String
  public let state: DomainState
  public let recordCount: Int
  /// 服务端返回的原始时间串(非 ISO8601,展示层原样或自行格式化)
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

/// 记录列表响应里附带的域名摘要——`grade` 是表单元数据的权威来源。
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

// MARK: - 记录

public struct DNSRecord: Hashable, Sendable, Identifiable {
  public let id: RecordID
  /// 主机记录,`@` 表示根域
  public let name: String
  public let type: String
  public let line: String
  public let value: String
  public let isEnabled: Bool
  public let mx: Int
  public let ttl: Int
  public let remark: String

  public init(
    id: RecordID, name: String, type: String, line: String, value: String,
    isEnabled: Bool, mx: Int, ttl: Int, remark: String
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
  }

  public static func == (lhs: DNSRecord, rhs: DNSRecord) -> Bool { lhs.id == rhs.id }
  public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// 记录草稿(表单层)。默认值在此补齐:`@` / MX=10 / TTL=600,与参考实现一致。
public struct RecordDraft: Hashable, Sendable {
  public var subDomain: String
  public var recordType: String
  public var recordLine: String
  public var value: String
  public var mx: Int
  public var ttl: Int
  public var remark: String

  public init(
    subDomain: String = "@",
    recordType: String = "A",
    recordLine: String = "默认",
    value: String,
    mx: Int? = nil,
    ttl: Int? = nil,
    remark: String = ""
  ) {
    self.subDomain = subDomain.isEmpty ? "@" : subDomain
    self.recordType = recordType
    self.recordLine = recordLine
    self.value = value
    // MX 空填 10、TTL 空填 600(仅当调用方未显式给值;与参考实现一致)
    self.mx = mx ?? 10
    self.ttl = ttl ?? 600
    self.remark = remark
  }
}

/// 记录列表页——首日就按分页建模,TC3 强分页接入时不改调用方。
public struct RecordListPage: Sendable {
  public let records: [DNSRecord]
  public let domain: DomainSummary
  /// Legacy 一次拉全量,恒为 false;分页实现填真实值
  public let hasMore: Bool

  public init(records: [DNSRecord], domain: DomainSummary, hasMore: Bool = false) {
    self.records = records
    self.domain = domain
    self.hasMore = hasMore
  }
}

/// 记录表单元数据:可选类型 + 可用线路。
public struct RecordOptions: Hashable, Sendable {
  public let types: [String]
  public let lines: [String]

  public init(types: [String], lines: [String]) {
    self.types = types
    self.lines = lines
  }
}

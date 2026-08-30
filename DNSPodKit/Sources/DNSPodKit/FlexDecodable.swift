import Foundation

// MARK: - FlexDecodable
//
// DNSPod 的 JSON 把数字当字符串返回(`enabled`/`mx`/`ttl`/`records`/各类 id),
// 偶尔又是真数字。以下容器类型对两种形态都容错,这是 Kit 存在的核心原因之一。

/// Int 或数字字符串 → Int
public struct FlexInt: Codable, Sendable, Hashable {
  public let value: Int

  public init(_ value: Int) { self.value = value }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let int = try? container.decode(Int.self) {
      value = int
    } else if let string = try? container.decode(String.self),
      let int = Int(string.trimmingCharacters(in: .whitespaces))
    {
      value = int
    } else if let double = try? container.decode(Double.self) {
      value = Int(double)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "FlexInt: 既不是数字也不是数字字符串")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(value)
  }
}

/// `"0"`/`"1"`/`0`/`1`/`"enable"` 等 → Bool
public struct FlexBool: Codable, Sendable, Hashable {
  public let value: Bool

  public init(_ value: Bool) { self.value = value }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let bool = try? container.decode(Bool.self) {
      value = bool
    } else if let int = try? container.decode(Int.self) {
      value = int != 0
    } else if let string = try? container.decode(String.self) {
      switch string.trimmingCharacters(in: .whitespaces).lowercased() {
      case "1", "true", "enable", "enabled", "on", "yes":
        value = true
      case "0", "false", "disable", "disabled", "off", "no", "":
        value = false
      default:
        throw DecodingError.dataCorruptedError(
          in: container, debugDescription: "FlexBool: 无法识别的布尔形态 \(string)")
      }
    } else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "FlexBool: 既不是布尔也不是字符串")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(value)
  }
}

/// Int/Double/String → String(id 类字段防脆裂)
public struct FlexString: Codable, Sendable, Hashable {
  public let value: String

  public init(_ value: String) { self.value = value }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let string = try? container.decode(String.self) {
      value = string
    } else if let int = try? container.decode(Int.self) {
      value = String(int)
    } else if let double = try? container.decode(Double.self) {
      value = String(double)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "FlexString: 无法转换为字符串")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(value)
  }
}

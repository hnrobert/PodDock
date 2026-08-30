import Foundation

/// application/x-www-form-urlencoded 编码。
///
/// 关键约束:`record_line_id` 的值形如 `10=0`,其中的 `=` 必须转义为 `%3D`,
/// 否则 DNSPod 解析错位;中文线路名按 UTF-8 百分号编码。
/// 字段按 key 排序,保证请求构造可被确定性断言。
public enum FormEncoder {
  public static func encode(_ fields: [String: String]) -> String {
    fields
      .sorted { $0.key < $1.key }
      .map { "\(percentEncode($0.key))=\(percentEncode($0.value))" }
      .joined(separator: "&")
  }

  public static func encodeData(_ fields: [String: String]) -> Data {
    Data(encode(fields).utf8)
  }

  /// 逆解码(仅供测试与 mock 断言)
  public static func decode(_ query: String) -> [String: String] {
    var result: [String: String] = [:]
    for pair in query.split(separator: "&") {
      let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2 else { continue }
      let key = percentDecode(String(parts[0]))
      let value = percentDecode(String(parts[1]))
      result[key] = value
    }
    return result
  }

  static func percentEncode(_ string: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
  }

  static func percentDecode(_ string: String) -> String {
    string.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? string
  }
}

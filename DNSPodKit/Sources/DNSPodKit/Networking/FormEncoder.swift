import Foundation

/// application/x-www-form-urlencoded encoding.
///
/// Key constraint: `record_line_id` looks like `10=0` — the `=` must escape to `%3D`,
/// or DNSPod mis-parses; Chinese line names percent-encode as UTF-8.
/// Fields sorted by key so request construction asserts deterministically.
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

  /// Inverse decode (tests and mock assertions only)
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

import Testing
import Foundation
@testable import DNSPodKit

@Suite("Form encoding")
struct FormEncoderTests {
  @Test("record_line_id escapes = as %3D")
  func escapesEquals() {
    let encoded = FormEncoder.encode(["record_line_id": "10=0"])
    #expect(encoded == "record_line_id=10%3D0")
  }

  @Test("Chinese line names percent-encode as UTF-8")
  func encodesUnicode() {
    let encoded = FormEncoder.encode(["record_line": "默认"])
    #expect(encoded == "record_line=%E9%BB%98%E8%AE%A4")
  }

  @Test("key ordering is deterministic (assertable)")
  func deterministicOrder() {
    let encoded = FormEncoder.encode(["b": "2", "a": "1"])
    #expect(encoded == "a=1&b=2")
  }

  @Test("decode inverts encode")
  func roundTrip() {
    let fields = ["domain_id": "2317346", "record_line": "默认", "x": "a=b&c"]
    let decoded = FormEncoder.decode(FormEncoder.encode(fields))
    #expect(decoded == fields)
  }
}

import Testing
import Foundation
@testable import DNSPodKit

@Suite("表单编码")
struct FormEncoderTests {
  @Test("record_line_id 的 = 必须转义为 %3D")
  func escapesEquals() {
    let encoded = FormEncoder.encode(["record_line_id": "10=0"])
    #expect(encoded == "record_line_id=10%3D0")
  }

  @Test("中文线路名按 UTF-8 百分号编码")
  func encodesUnicode() {
    let encoded = FormEncoder.encode(["record_line": "默认"])
    #expect(encoded == "record_line=%E9%BB%98%E8%AE%A4")
  }

  @Test("键排序保证确定性(可断言)")
  func deterministicOrder() {
    let encoded = FormEncoder.encode(["b": "2", "a": "1"])
    #expect(encoded == "a=1&b=2")
  }

  @Test("解码还原(decode 是 encode 的逆)")
  func roundTrip() {
    let fields = ["domain_id": "2317346", "record_line": "默认", "x": "a=b&c"]
    let decoded = FormEncoder.decode(FormEncoder.encode(fields))
    #expect(decoded == fields)
  }
}

import Testing
import Foundation
@testable import DNSPodKit

@Suite("FlexDecodable 容错解码")
struct FlexDecodableTests {
  @Test("Int:真数字与数字字符串都解")
  func flexInt() throws {
    let asNumber = try JSONDecoder().decode(FlexInt.self, from: Data("42".utf8))
    #expect(asNumber.value == 42)
    let asString = try JSONDecoder().decode(FlexInt.self, from: Data("\"600\"".utf8))
    #expect(asString.value == 600)
  }

  @Test("Bool:1/0/字符串布尔/enable 形态都解")
  func flexBool() throws {
    func decode(_ json: String) throws -> Bool {
      try JSONDecoder().decode(FlexBool.self, from: Data(json.utf8)).value
    }
    #expect(try decode("true"))
    #expect(try decode("1"))
    #expect(try decode("\"1\""))
    #expect(try decode("\"enable\""))
    #expect(try decode("false") == false)
    #expect(try decode("\"0\"") == false)
    #expect(try decode("\"disable\"") == false)
  }

  @Test("String:id 类字段从数字或字符串都解")
  func flexString() throws {
    let asNumber = try JSONDecoder().decode(FlexString.self, from: Data("2317346".utf8))
    #expect(asNumber.value == "2317346")
    let asString = try JSONDecoder().decode(FlexString.self, from: Data("\"2317346\"".utf8))
    #expect(asString.value == "2317346")
  }

  @Test("无法解析时抛错而不是静默给默认值")
  func flexIntRejectsGarbage() {
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(FlexInt.self, from: Data("\"abc\"".utf8))
    }
  }
}

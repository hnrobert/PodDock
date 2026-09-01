import Testing
import Foundation
@testable import DNSPodKit

@Suite("FlexDecodable tolerant decoding")
struct FlexDecodableTests {
  @Test("Int decodes real numbers and numeric strings")
  func flexInt() throws {
    let asNumber = try JSONDecoder().decode(FlexInt.self, from: Data("42".utf8))
    #expect(asNumber.value == 42)
    let asString = try JSONDecoder().decode(FlexInt.self, from: Data("\"600\"".utf8))
    #expect(asString.value == 600)
  }

  @Test("Bool decodes 1/0/string booleans/enable forms")
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

  @Test("String decodes id fields from numbers or strings")
  func flexString() throws {
    let asNumber = try JSONDecoder().decode(FlexString.self, from: Data("2317346".utf8))
    #expect(asNumber.value == "2317346")
    let asString = try JSONDecoder().decode(FlexString.self, from: Data("\"2317346\"".utf8))
    #expect(asString.value == "2317346")
  }

  @Test("throws on unparseable input instead of a silent default")
  func flexIntRejectsGarbage() {
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(FlexInt.self, from: Data("\"abc\"".utf8))
    }
  }
}

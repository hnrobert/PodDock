import Testing
import Foundation
@testable import DNSPodKit

// MARK: - Fixtures
//
// Shapes from the reference and docs.dnspod.cn samples; M1 replaces these with real-token Fixtures/*.json.

enum Fixtures {
  static let domainList = """
    {"status":{"code":"1","message":"Action completed successful"},"domains":[
      {"id":"2317346","name":"example.com","grade":"DP_Free","status":"enable","records":"12","updated_on":"2024-01-01 12:00:00"},
      {"id":"2317347","name":"example.net","grade":"D_Free","status":"pause","records":"3","updated_on":"2024-06-01 08:30:00"},
      {"id":"2317348","name":"example.org","grade":"WEIRD_FUTURE_GRADE","status":"spam","records":"0","updated_on":""}
    ]}
    """

  static let recordList = """
    {"status":{"code":1,"message":"ok"},
     "domain":{"id":"2317346","name":"example.com","grade":"DP_Free"},
     "records":[
      {"id":"154169992","name":"www","type":"A","line":"默认","value":"1.2.3.4","enabled":"1","mx":"0","ttl":"600","remark":""},
      {"id":"154169993","name":"@","type":"MX","line":"默认","value":"mx.example.com.","enabled":"0","mx":"10","ttl":"600","remark":"mail"},
      {"id":154169994,"name":"api","type":"CNAME","line":"联通","value":"cdn.example.net","enabled":true,"mx":0,"ttl":120,"remark":"边缘"}
    ]}
    """

  static let recordInfo = """
    {"status":{"code":1,"message":"ok"},
     "record":{"id":"154169992","sub_domain":"www","record_type":"A","record_line":"默认","value":"1.2.3.4","mx":"0","ttl":"600","remark":"主站"}}
    """

  static let recordCreate = """
    {"status":{"code":"1","message":"Action completed successful"},"record":{"id":"154169995","name":"api"}}
    """

  static let recordTypes = """
    {"status":{"code":1,"message":"ok"},"types":["A","CNAME","MX","TXT","AAAA","NS","SRV","CAA"]}
    """

  static let recordLines = """
    {"status":{"code":1,"message":"ok"},"lines":["默认","电信","联通","移动"]}
    """

  static let ok = """
    {"status":{"code":1,"message":"Action completed successful"}}
    """

  static let authFailure = """
    {"status":{"code":6,"message":"登录密码错误"}}
    """
}

@Suite("LegacyClient request building and decoding")
struct LegacyClientTests {
  static let tokenID = "12345"
  static let tokenKey = "abcXYZ"

  private func makeClient(_ mock: MockTransport) -> LegacyClient {
    LegacyClient(tokenID: Self.tokenID, tokenKey: Self.tokenKey, transport: mock)
  }

  private func body(of request: HTTPRequest) throws -> [String: String] {
    guard let body = request.body else { return [:] }
    return FormEncoder.decode(String(decoding: body, as: UTF8.self))
  }

  @Test("common params and login_token assembly")
  func commonParams() async throws {
    let mock = MockTransport()
    await mock.enqueue(ok: Fixtures.domainList)
    let client = makeClient(mock)

    _ = try await client.listDomains()

    let request = await mock.requests[0]
    #expect(request.url.absoluteString == "https://dnsapi.cn/Domain.List")
    #expect(request.method == "POST")
    #expect(request.headers["Content-Type"] == "application/x-www-form-urlencoded")
    let fields = try body(of: request)
    #expect(fields["login_token"] == "12345,abcXYZ")
    #expect(fields["format"] == "json")
    #expect(fields["lang"] == "cn")
    #expect(fields["error_on_empty"] == "no")
  }

  @Test("domain list decoding: string-numbered status, unknown grade doesn't crash")
  func domainListDecoding() async throws {
    let mock = MockTransport()
    await mock.enqueue(ok: Fixtures.domainList)
    let client = makeClient(mock)

    let domains = try await client.listDomains()
    #expect(domains.count == 3)
    let first = domains[0]
    #expect(first.id == DomainID("2317346"))
    #expect(first.name == "example.com")
    #expect(first.grade == "DP_Free")
    #expect(first.state == .enable)
    #expect(first.recordCount == 12)
    let second = domains[1]
    #expect(second.state == .pause)
    // Unknown grades pass through verbatim (the reference app KeyErrors into a 500 here)
    #expect(domains[2].grade == "WEIRD_FUTURE_GRADE")
    #expect(domains[2].state == .spam)
    #expect(domains[2].recordCount == 0)
  }

  @Test("record list decoding: string and real numbers both decode")
  func recordListDecoding() async throws {
    let mock = MockTransport()
    await mock.enqueue(ok: Fixtures.recordList)
    let client = makeClient(mock)

    let page = try await client.listRecords(domainID: DomainID("2317346"))
    #expect(page.domain.grade == "DP_Free")
    #expect(page.hasMore == false)
    #expect(page.records.count == 3)

    let www = page.records[0]
    #expect(www.name == "www")
    #expect(www.type == "A")
    #expect(www.isEnabled)
    #expect(www.ttl == 600)

    let mx = page.records[1]
    #expect(mx.name == "@")
    #expect(mx.type == "MX")
    #expect(mx.isEnabled == false)
    #expect(mx.mx == 10)
    #expect(mx.remark == "mail")

    // The third uses real numbers/bools and must decode too
    let api = page.records[2]
    #expect(api.id == RecordID("154169994"))
    #expect(api.line == "联通")
    #expect(api.ttl == 120)
  }

  @Test("Record.Info normalizes record_type/record_line keys")
  func recordInfoDecoding() async throws {
    let mock = MockTransport()
    await mock.enqueue(ok: Fixtures.recordInfo)
    let client = makeClient(mock)

    let record = try await client.fetchRecord(id: RecordID("154169992"), domainID: DomainID("2317346"))
    #expect(record.name == "www")
    #expect(record.type == "A")
    #expect(record.line == "默认")
    #expect(record.remark == "主站")
  }

  @Test("Domain.Status sends enable/disable on the wire")
  func domainStatusWire() async throws {
    let mock = MockTransport()
    await mock.enqueue(ok: Fixtures.ok)
    await mock.enqueue(ok: Fixtures.ok)
    let client = makeClient(mock)

    try await client.setDomainStatus(id: DomainID("2317346"), to: .disable)
    try await client.setDomainStatus(id: DomainID("2317346"), to: .enable)

    let requests = await mock.requests
    #expect(requests.map(\.url.lastPathComponent) == ["Domain.Status", "Domain.Status"])
    #expect(try body(of: requests[0])["status"] == "disable")
    #expect(try body(of: requests[1])["status"] == "enable")
  }

  @Test("Record.Create fields and defaults; non-empty remark triggers exactly one Remark")
  func createRecordWithRemark() async throws {
    let mock = MockTransport()
    await mock.enqueue(ok: Fixtures.recordCreate)
    await mock.enqueue(ok: Fixtures.ok)
    let client = makeClient(mock)

    let domain = DNSDomain(
      id: DomainID("2317346"), name: "example.com", grade: "DP_Free",
      state: .enable, recordCount: 0, updatedOn: "")
    let draft = RecordDraft(
      subDomain: "", recordType: "A", recordLine: "默认",
      value: "1.2.3.4", remark: "新站")

    let recordID = try await client.createRecord(draft, in: domain)
    #expect(recordID == RecordID("154169995"))

    let requests = await mock.requests
    #expect(requests.count == 2)
    let create = try body(of: requests[0])
    #expect(requests[0].url.lastPathComponent == "Record.Create")
    // Empty host becomes @; MX/TTL defaults filled at the draft layer
    #expect(create["sub_domain"] == "@")
    #expect(create["record_type"] == "A")
    #expect(create["record_line"] == "默认")
    #expect(create["value"] == "1.2.3.4")
    #expect(create["mx"] == "10")
    #expect(create["ttl"] == "600")

    #expect(requests[1].url.lastPathComponent == "Record.Remark")
    let remark = try body(of: requests[1])
    #expect(remark["record_id"] == "154169995")
    #expect(remark["remark"] == "新站")
  }

  @Test("Record.Create without a remark skips the Remark call")
  func createRecordWithoutRemark() async throws {
    let mock = MockTransport()
    await mock.enqueue(ok: Fixtures.recordCreate)
    let client = makeClient(mock)

    let domain = DNSDomain(
      id: DomainID("2317346"), name: "example.com", grade: "DP_Free",
      state: .enable, recordCount: 0, updatedOn: "")
    let draft = RecordDraft(subDomain: "www", recordType: "A", recordLine: "默认", value: "1.2.3.4")

    _ = try await client.createRecord(draft, in: domain)
    let count = await mock.requests.count
    #expect(count == 1)
  }

  @Test("updateRecord: remark change triggers Remark; unchanged calls only Modify")
  func updateRecordRemarkDiff() async throws {
    let mock = MockTransport()
    await mock.enqueue(ok: Fixtures.ok)
    await mock.enqueue(ok: Fixtures.ok)
    let client = makeClient(mock)

    let domain = DNSDomain(
      id: DomainID("2317346"), name: "example.com", grade: "DP_Free",
      state: .enable, recordCount: 0, updatedOn: "")
    let original = DNSRecord(
      id: RecordID("154169992"), name: "www", type: "A", line: "默认", value: "1.2.3.4",
      isEnabled: true, mx: 0, ttl: 600, remark: "旧备注")
    let draft = RecordDraft(
      subDomain: "www", recordType: "A", recordLine: "默认",
      value: "5.6.7.8", ttl: 300, remark: "新备注")

    try await client.updateRecord(id: original.id, in: domain, from: original, to: draft)

    var requests = await mock.requests
    #expect(requests.count == 2)
    #expect(requests[0].url.lastPathComponent == "Record.Modify")
    let modify = try body(of: requests[0])
    #expect(modify["record_id"] == "154169992")
    #expect(modify["value"] == "5.6.7.8")
    #expect(modify["ttl"] == "300")
    #expect(requests[1].url.lastPathComponent == "Record.Remark")

    // Remark unchanged → a single Modify call
    let mock2 = MockTransport()
    await mock2.enqueue(ok: Fixtures.ok)
    let client2 = makeClient(mock2)
    let sameRemarkDraft = RecordDraft(
      subDomain: "www", recordType: "A", recordLine: "默认",
      value: "1.2.3.4", ttl: 600, remark: "旧备注")
    try await client2.updateRecord(id: original.id, in: domain, from: original, to: sameRemarkDraft)
    requests = await mock2.requests
    #expect(requests.count == 1)
  }

  @Test("envelope errors map to DNSPodError.api with detectable auth failures")
  func errorMapping() async throws {
    let mock = MockTransport()
    await mock.enqueue(ok: Fixtures.authFailure)
    await mock.enqueue(ok: Fixtures.authFailure)
    let client = makeClient(mock)

    await #expect(throws: DNSPodError.self) {
      _ = try await client.listDomains()
    }
    // Verify the normalized result directly
    do {
      _ = try await client.listDomains()
      Issue.record("应抛错")
    } catch let error as DNSPodError {
      guard case .api(let code, let message) = error else {
        Issue.record("应为 .api,实际 \(error)")
        return
      }
      #expect(code == 6)
      #expect(message == "登录密码错误")
      #expect(error.isAuthenticationFailure)
    }
  }

  @Test("remark write failure degrades to remarkFailed (main op already succeeded)")
  func remarkPartialFailure() async throws {
    let mock = MockTransport()
    await mock.enqueue(ok: Fixtures.recordCreate)
    await mock.enqueue(ok: Fixtures.authFailure)
    let client = makeClient(mock)

    let domain = DNSDomain(
      id: DomainID("2317346"), name: "example.com", grade: "DP_Free",
      state: .enable, recordCount: 0, updatedOn: "")
    let draft = RecordDraft(subDomain: "www", recordType: "A", recordLine: "默认", value: "1.2.3.4", remark: "备注")

    do {
      _ = try await client.createRecord(draft, in: domain)
      Issue.record("应抛 remarkFailed")
    } catch let error as DNSPodError {
      guard case .remarkFailed = error else {
        Issue.record("应为 .remarkFailed,实际 \(error)")
        return
      }
      // Underlying is auth failure → partial failure should still kick back to accounts
      #expect(error.isAuthenticationFailure)
    }
  }

  @Test("non-2xx maps to transport error; HTTP 401 normalizes to auth failure")
  func httpError() async throws {
    let mock = MockTransport()
    await mock.enqueue(.success(HTTPResponse(statusCode: 502, body: Data("bad gateway".utf8))))
    await mock.enqueue(.success(HTTPResponse(statusCode: 401, body: Data("".utf8))))
    let client = makeClient(mock)

    do {
      _ = try await client.listDomains()
      Issue.record("应抛错")
    } catch let error as DNSPodError {
      guard case .transport = error else {
        Issue.record("应为 .transport,实际 \(error)")
        return
      }
    }

    // 401 → .api(401), treated as auth failure (kick back to account page / login prompt)
    do {
      _ = try await client.listDomains()
      Issue.record("应抛错")
    } catch let error as DNSPodError {
      guard case .api(let code, _) = error else {
        Issue.record("应为 .api(401),实际 \(error)")
        return
      }
      #expect(code == 401)
      #expect(error.isAuthenticationFailure)
    }
  }

  @Test("recordOptions: Record.Type uses domain_grade; Line uses domain_id + domain_grade")
  func recordOptionsWire() async throws {
    let mock = MockTransport()
    await mock.enqueue(ok: Fixtures.recordTypes)
    await mock.enqueue(ok: Fixtures.recordLines)
    let client = makeClient(mock)

    let domain = DNSDomain(
      id: DomainID("2317346"), name: "example.com", grade: "DP_Free",
      state: .enable, recordCount: 0, updatedOn: "")
    let options = try await client.recordOptions(for: domain)
    #expect(options.types == ["A", "CNAME", "MX", "TXT", "AAAA", "NS", "SRV", "CAA"])
    #expect(options.lines == ["默认", "电信", "联通", "移动"])

    let requests = await mock.requests
    #expect(requests[0].url.lastPathComponent == "Record.Type")
    #expect(try body(of: requests[0])["domain_grade"] == "DP_Free")
    #expect(requests[1].url.lastPathComponent == "Record.Line")
    let lineFields = try body(of: requests[1])
    #expect(lineFields["domain_id"] == "2317346")
    #expect(lineFields["domain_grade"] == "DP_Free")
  }
}

@Suite("Weight wire format")
struct WeightTests {
  static let tokenID = "12345"
  static let tokenKey = "abc"

  @Test("weight goes on the wire when set, absent when nil")
  func weightWire() async throws {
    let mock = MockTransport()
    await mock.enqueue(ok: Fixtures.recordCreate)
    await mock.enqueue(ok: Fixtures.ok)
    let client = LegacyClient(tokenID: Self.tokenID, tokenKey: Self.tokenKey, transport: mock)

    let domain = DNSDomain(
      id: DomainID("2317346"), name: "example.com", grade: "DP_Free",
      state: .enable, recordCount: 0, updatedOn: "")
    _ = try await client.createRecord(
      RecordDraft(subDomain: "www", recordType: "A", recordLine: "默认", value: "1.2.3.4", weight: 30),
      in: domain)
    let create = await mock.recordedFormBodies()[0]
    #expect(create["weight"] == "30")

    let mock2 = MockTransport()
    await mock2.enqueue(ok: Fixtures.recordCreate)
    let client2 = LegacyClient(tokenID: Self.tokenID, tokenKey: Self.tokenKey, transport: mock2)
    _ = try await client2.createRecord(
      RecordDraft(subDomain: "www", recordType: "A", recordLine: "默认", value: "1.2.3.4"),
      in: domain)
    let create2 = await mock2.recordedFormBodies()[0]
    #expect(create2["weight"] == nil)

    // modify keeps weight when the draft doesn't set one
    let mock3 = MockTransport()
    await mock3.enqueue(ok: Fixtures.ok)
    let client3 = LegacyClient(tokenID: Self.tokenID, tokenKey: Self.tokenKey, transport: mock3)
    let original = DNSRecord(
      id: RecordID("154169992"), name: "www", type: "A", line: "默认", value: "1.2.3.4",
      isEnabled: true, mx: 0, ttl: 600, remark: "", weight: 30)
    try await client3.updateRecord(
      id: original.id, in: domain, from: original,
      to: RecordDraft(subDomain: "www", recordType: "A", recordLine: "默认", value: "5.6.7.8"))
    let modify = await mock3.recordedFormBodies()[0]
    #expect(modify["weight"] == nil)

    // Record.List: null weight decodes to nil, numeric string decodes
    #expect(try JSONDecoder().decode(RecordListResponse.self, from: Data(Fixtures.recordList.utf8)).records?[0].weight == nil)
  }
}

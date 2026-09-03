import Foundation

/// Legacy API impl (https://dnsapi.cn + login_token form POST).
///
/// Common params injected by `rawCall`: `login_token`=`ID,Token`, `format=json`,
/// `lang=cn`, `error_on_empty=no`; success is `status.code == 1`.
/// Main accounts only, officially legacy — hedged by the adapter layer; behavioral quirks stay contained here.
public struct LegacyClient: DNSPodClient {
  public var capabilities: Set<DNSPodCapability> { [] }

  public static let defaultBaseURL = URL(string: "https://dnsapi.cn")!
  public static let defaultUserAgent = "PodDock/0.1.0 (+https://github.com/PodDock/PodDock)"

  private let transport: HTTPTransport
  private let tokenID: String
  private let tokenKey: String
  private let baseURL: URL
  private let userAgent: String
  /// Server error language (legacy API supports cn/en); the App picks by system language
  private let lang: String
  private let optionsProvider: RecordOptionsProvider

  public init(
    tokenID: String,
    tokenKey: String,
    transport: HTTPTransport = URLSessionTransport(),
    baseURL: URL = LegacyClient.defaultBaseURL,
    userAgent: String = LegacyClient.defaultUserAgent,
    lang: String = "cn",
    optionsProvider: RecordOptionsProvider? = nil
  ) {
    self.tokenID = tokenID
    self.tokenKey = tokenKey
    self.transport = transport
    self.baseURL = baseURL
    self.userAgent = userAgent
    self.lang = lang
    // types cached by grade, lines by domain_id — legacy-API knowledge kept inside the Kit
    self.optionsProvider = optionsProvider ?? RecordOptionsProvider(
      fetchTypes: { [transport, baseURL, userAgent, tokenID, tokenKey, lang] grade in
        let response: RecordTypesResponse = try await LegacyClient.rawDecoded(
          action: "Record.Type",
          params: ["domain_grade": grade],
          transport: transport, tokenID: tokenID, tokenKey: tokenKey,
          baseURL: baseURL, userAgent: userAgent, lang: lang
        )
        return response.types ?? []
      },
      fetchLines: { [transport, baseURL, userAgent, tokenID, tokenKey, lang] domainID, grade in
        let response: RecordLinesResponse = try await LegacyClient.rawDecoded(
          action: "Record.Line",
          params: ["domain_id": domainID.rawValue, "domain_grade": grade],
          transport: transport, tokenID: tokenID, tokenKey: tokenKey,
          baseURL: baseURL, userAgent: userAgent, lang: lang
        )
        return response.lines ?? []
      }
    )
  }

  // MARK: - Accounts & domains

  public func validateCredentials() async throws {
    // error_on_empty=no: empty accounts still return code 1, so a successful list means valid credentials
    _ = try await listDomains()
  }

  public func listDomains() async throws -> [DNSDomain] {
    let response: DomainListResponse = try await call("Domain.List", [:])
    return (response.domains ?? []).compactMap(\.toDomain)
  }

  public func createDomain(name: String) async throws {
    let _: StatusOnlyResponse = try await call("Domain.Create", ["domain": name])
  }

  public func setDomainStatus(id: DomainID, to status: ToggleStatus) async throws {
    // The reference sends enable/disable (docs say enable|pause); copy the reference for now, verify against a live domain in M1
    let _: StatusOnlyResponse = try await call(
      "Domain.Status", ["domain_id": id.rawValue, "status": status.rawValue])
  }

  public func removeDomain(id: DomainID) async throws {
    let _: StatusOnlyResponse = try await call("Domain.Remove", ["domain_id": id.rawValue])
  }

  // MARK: - Records

  public func listRecords(domainID: DomainID) async throws -> RecordListPage {
    let response: RecordListResponse = try await call("Record.List", ["domain_id": domainID.rawValue])
    let summary =
      response.domain?.toSummary
      ?? DomainSummary(id: domainID, name: "", grade: "")
    return RecordListPage(
      records: (response.records ?? []).map(\.toRecord),
      domain: summary
    )
  }

  public func fetchRecord(id: RecordID, domainID: DomainID) async throws -> DNSRecord {
    let response: RecordInfoResponse = try await call(
      "Record.Info", ["domain_id": domainID.rawValue, "record_id": id.rawValue])
    guard let record = response.record else {
      throw DNSPodError.invalidResponse("Record.Info 未返回 record 对象")
    }
    return record.toRecord
  }

  public func recordOptions(for domain: DNSDomain) async throws -> RecordOptions {
    try await optionsProvider.options(for: domain)
  }

  public func createRecord(_ draft: RecordDraft, in domain: DNSDomain) async throws -> RecordID {
    let response: RecordCreateResponse = try await call(
      "Record.Create",
      Self.recordFields(for: draft, domainID: domain.id.rawValue))
    guard let rawID = response.record?.id?.value, !rawID.isEmpty else {
      throw DNSPodError.invalidResponse("Record.Create 未返回 record.id")
    }
    let recordID = RecordID(rawValue: rawID)

    // Created with a non-empty remark → follow up with Remark (two non-atomic calls; failure degrades to partial failure)
    if !draft.remark.isEmpty {
      do {
        try await setRecordRemark(id: recordID, domainID: domain.id, remark: draft.remark)
      } catch let error as DNSPodError {
        throw DNSPodError.remarkFailed(underlying: error)
      }
    }
    return recordID
  }

  public func updateRecord(
    id: RecordID, in domain: DNSDomain, from original: DNSRecord, to draft: RecordDraft
  ) async throws {
    var fields = Self.recordFields(for: draft, domainID: domain.id.rawValue)
    fields["record_id"] = id.rawValue
    let _: StatusOnlyResponse = try await call("Record.Modify", fields)

    // Reference app: only calls it when remark != oremark
    if draft.remark != original.remark {
      do {
        try await setRecordRemark(id: id, domainID: domain.id, remark: draft.remark)
      } catch let error as DNSPodError {
        throw DNSPodError.remarkFailed(underlying: error)
      }
    }
  }

  public func setRecordStatus(id: RecordID, domainID: DomainID, to status: ToggleStatus) async throws {
    let _: StatusOnlyResponse = try await call(
      "Record.Status",
      [
        "domain_id": domainID.rawValue,
        "record_id": id.rawValue,
        "status": status.rawValue,
      ])
  }

  public func removeRecord(id: RecordID, domainID: DomainID) async throws {
    let _: StatusOnlyResponse = try await call(
      "Record.Remove", ["domain_id": domainID.rawValue, "record_id": id.rawValue])
  }

  public func setRecordRemark(id: RecordID, domainID: DomainID, remark: String) async throws {
    let _: StatusOnlyResponse = try await call(
      "Record.Remark",
      ["domain_id": domainID.rawValue, "record_id": id.rawValue, "remark": remark])
  }

  // MARK: - Low-level call

  /// Shared Create/Modify wire fields; weight only goes on the wire when set
  /// (nil keeps the server default on create / the existing value on modify)
  static func recordFields(for draft: RecordDraft, domainID: String) -> [String: String] {
    var fields: [String: String] = [
      "domain_id": domainID,
      "sub_domain": draft.subDomain,
      "record_type": draft.recordType,
      "record_line": draft.recordLine,
      "value": draft.value,
      "mx": String(draft.mx),
      "ttl": String(draft.ttl),
    ]
    if let weight = draft.weight {
      fields["weight"] = String(weight)
    }
    return fields
  }

  /// Debug/fixture capture: returns the raw body after the envelope check.
  /// Lets poddock-capture record real responses into Tests/DNSPodKitTests/Fixtures/.
  public func rawResponse(_ action: String, _ params: [String: String]) async throws -> Data {
    try await Self.raw(
      action: action, params: params,
      transport: transport, tokenID: tokenID, tokenKey: tokenKey,
      baseURL: baseURL, userAgent: userAgent, lang: lang)
  }

  private func call<T: Decodable>(_ action: String, _ params: [String: String]) async throws -> T {
    try await Self.rawDecoded(
      action: action, params: params,
      transport: transport, tokenID: tokenID, tokenKey: tokenKey,
      baseURL: baseURL, userAgent: userAgent, lang: lang)
  }

  /// One legacy-API call with envelope checking (static so optionsProvider closures reuse it).
  ///
  /// Runs on the cooperative pool (Task.detached): under SE-0461 nonisolated async inherits the caller's
  /// actor — called from the UI, network round-trips and JSON decoding serialize onto the main thread; slow networks freeze.
  static func raw(
    action: String,
    params: [String: String],
    transport: HTTPTransport,
    tokenID: String,
    tokenKey: String,
    baseURL: URL,
    userAgent: String,
    lang: String = "cn"
  ) async throws -> Data {
    try await Task.detached(priority: .userInitiated) {
      try await rawOnCooperativePool(
        action: action, params: params,
        transport: transport, tokenID: tokenID, tokenKey: tokenKey,
        baseURL: baseURL, userAgent: userAgent, lang: lang)
    }.value
  }

  private static func rawOnCooperativePool(
    action: String,
    params: [String: String],
    transport: HTTPTransport,
    tokenID: String,
    tokenKey: String,
    baseURL: URL,
    userAgent: String,
    lang: String
  ) async throws -> Data {
    var fields = params
    fields["login_token"] = "\(tokenID),\(tokenKey)"
    fields["format"] = "json"
    fields["lang"] = lang
    fields["error_on_empty"] = "no"

    let request = HTTPRequest(
      url: baseURL.appendingPathComponent(action),
      method: "POST",
      headers: [
        "Content-Type": "application/x-www-form-urlencoded",
        "User-Agent": userAgent,
      ],
      body: FormEncoder.encodeData(fields)
    )

    let response: HTTPResponse
    do {
      response = try await transport.send(request)
    } catch {
      throw DNSPodError.transport(error.localizedDescription)
    }

    guard (200..<300).contains(response.statusCode) else {
      // DNSPod answers an invalid login_token with bare HTTP 401/403 (no envelope) — normalize to auth failure
      if response.statusCode == 401 || response.statusCode == 403 {
        throw DNSPodError.api(
          code: 401, message: "认证失败(HTTP \(response.statusCode)):Token 无效或已过期")
      }
      throw DNSPodError.transport("HTTP \(response.statusCode)")
    }

    // Envelope check: success only when status.code == 1
    struct Envelope: Codable {
      let status: LegacyStatusDTO
    }
    do {
      let envelope = try JSONDecoder().decode(Envelope.self, from: response.body)
      let code = envelope.status.code.value
      guard code == 1 else {
        throw DNSPodError.api(code: code, message: envelope.status.message)
      }
    } catch let error as DNSPodError {
      throw error
    } catch {
      throw DNSPodError.invalidResponse("响应无法解码为 JSON 信封")
    }
    return response.body
  }
}

extension LegacyClient {
  /// Generic helper: envelope check then decode (named distinctly from raw to avoid overload ambiguity)
  static func rawDecoded<T: Decodable>(
    action: String,
    params: [String: String],
    transport: HTTPTransport,
    tokenID: String,
    tokenKey: String,
    baseURL: URL,
    userAgent: String,
    lang: String = "cn"
  ) async throws -> T {
    let data = try await raw(
      action: action, params: params,
      transport: transport, tokenID: tokenID, tokenKey: tokenKey,
      baseURL: baseURL, userAgent: userAgent, lang: lang)
    do {
      return try JSONDecoder().decode(T.self, from: data)
    } catch {
      throw DNSPodError.invalidResponse("\(action) 响应结构不符合预期")
    }
  }
}

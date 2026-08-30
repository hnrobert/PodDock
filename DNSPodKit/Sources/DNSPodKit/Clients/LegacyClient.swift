import Foundation

/// 传统 API 实现(https://dnsapi.cn + login_token 表单 POST)。
///
/// 公共参数由 `rawCall` 统一注入:`login_token`=`ID,Token`、`format=json`、
/// `lang=cn`、`error_on_empty=no`;`status.code == 1` 为成功判定。
/// 仅主账号可用,官方已标 legacy——由适配层对冲,业务行为差异全部收敛在本实现内。
public struct LegacyClient: DNSPodClient {
  public var capabilities: Set<DNSPodCapability> { [] }

  public static let defaultBaseURL = URL(string: "https://dnsapi.cn")!
  public static let defaultUserAgent = "PodDock/0.1.0 (+https://github.com/PodDock/PodDock)"

  private let transport: HTTPTransport
  private let tokenID: String
  private let tokenKey: String
  private let baseURL: URL
  private let userAgent: String
  private let optionsProvider: RecordOptionsProvider

  public init(
    tokenID: String,
    tokenKey: String,
    transport: HTTPTransport = URLSessionTransport(),
    baseURL: URL = LegacyClient.defaultBaseURL,
    userAgent: String = LegacyClient.defaultUserAgent,
    optionsProvider: RecordOptionsProvider? = nil
  ) {
    self.tokenID = tokenID
    self.tokenKey = tokenKey
    self.transport = transport
    self.baseURL = baseURL
    self.userAgent = userAgent
    // type 按 grade 缓存、line 按 domain_id 缓存——传统 API 的行为知识,留在 Kit 内
    self.optionsProvider = optionsProvider ?? RecordOptionsProvider(
      fetchTypes: { [transport, baseURL, userAgent, tokenID, tokenKey] grade in
        let response: RecordTypesResponse = try await LegacyClient.rawDecoded(
          action: "Record.Type",
          params: ["domain_grade": grade],
          transport: transport, tokenID: tokenID, tokenKey: tokenKey,
          baseURL: baseURL, userAgent: userAgent
        )
        return response.types ?? []
      },
      fetchLines: { [transport, baseURL, userAgent, tokenID, tokenKey] domainID, grade in
        let response: RecordLinesResponse = try await LegacyClient.rawDecoded(
          action: "Record.Line",
          params: ["domain_id": domainID.rawValue, "domain_grade": grade],
          transport: transport, tokenID: tokenID, tokenKey: tokenKey,
          baseURL: baseURL, userAgent: userAgent
        )
        return response.lines ?? []
      }
    )
  }

  // MARK: - 账户与域名

  public func validateCredentials() async throws {
    // error_on_empty=no:空账户也返回 code 1,列表成功即凭据有效
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
    // 参考实现发 enable/disable(官方文档写 enable|pause),首版照抄参考实现,M1 实测校正
    let _: StatusOnlyResponse = try await call(
      "Domain.Status", ["domain_id": id.rawValue, "status": status.rawValue])
  }

  public func removeDomain(id: DomainID) async throws {
    let _: StatusOnlyResponse = try await call("Domain.Remove", ["domain_id": id.rawValue])
  }

  // MARK: - 记录

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
      [
        "domain_id": domain.id.rawValue,
        "sub_domain": draft.subDomain,
        "record_type": draft.recordType,
        "record_line": draft.recordLine,
        "value": draft.value,
        "mx": String(draft.mx),
        "ttl": String(draft.ttl),
      ])
    guard let rawID = response.record?.id?.value, !rawID.isEmpty else {
      throw DNSPodError.invalidResponse("Record.Create 未返回 record.id")
    }
    let recordID = RecordID(rawValue: rawID)

    // 创建成功且填写了备注 → 补调 Remark(两次调用不原子,失败降级为部分失败)
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
    let _: StatusOnlyResponse = try await call(
      "Record.Modify",
      [
        "domain_id": domain.id.rawValue,
        "record_id": id.rawValue,
        "sub_domain": draft.subDomain,
        "record_type": draft.recordType,
        "record_line": draft.recordLine,
        "value": draft.value,
        "mx": String(draft.mx),
        "ttl": String(draft.ttl),
      ])

    // 参考实现:remark != oremark 才补调
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

  // MARK: - 底层调用

  /// 调试 / fixture 抓取:信封校验后返回原始响应体。
  /// 供 poddock-capture 抓真实响应进 Tests/DNSPodKitTests/Fixtures/。
  public func rawResponse(_ action: String, _ params: [String: String]) async throws -> Data {
    try await Self.raw(
      action: action, params: params,
      transport: transport, tokenID: tokenID, tokenKey: tokenKey,
      baseURL: baseURL, userAgent: userAgent)
  }

  private func call<T: Decodable>(_ action: String, _ params: [String: String]) async throws -> T {
    try await Self.rawDecoded(
      action: action, params: params,
      transport: transport, tokenID: tokenID, tokenKey: tokenKey,
      baseURL: baseURL, userAgent: userAgent)
  }

  /// 发起一次传统 API 调用并完成信封校验(静态方法便于 optionsProvider 闭包复用)
  static func raw(
    action: String,
    params: [String: String],
    transport: HTTPTransport,
    tokenID: String,
    tokenKey: String,
    baseURL: URL,
    userAgent: String
  ) async throws -> Data {
    var fields = params
    fields["login_token"] = "\(tokenID),\(tokenKey)"
    fields["format"] = "json"
    fields["lang"] = "cn"
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
      // DNSPod 对无效 login_token 直接回 HTTP 401/403(不带业务信封)——归一为认证失败
      if response.statusCode == 401 || response.statusCode == 403 {
        throw DNSPodError.api(
          code: 401, message: "认证失败(HTTP \(response.statusCode)):Token 无效或已过期")
      }
      throw DNSPodError.transport("HTTP \(response.statusCode)")
    }

    // 信封校验:status.code == 1 才算成功
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
  /// 泛型便捷重载:信封校验后直接解码目标类型(与返回 Data 的 raw 区分命名,避免重载歧义)
  static func rawDecoded<T: Decodable>(
    action: String,
    params: [String: String],
    transport: HTTPTransport,
    tokenID: String,
    tokenKey: String,
    baseURL: URL,
    userAgent: String
  ) async throws -> T {
    let data = try await raw(
      action: action, params: params,
      transport: transport, tokenID: tokenID, tokenKey: tokenKey,
      baseURL: baseURL, userAgent: userAgent)
    do {
      return try JSONDecoder().decode(T.self, from: data)
    } catch {
      throw DNSPodError.invalidResponse("\(action) 响应结构不符合预期")
    }
  }
}

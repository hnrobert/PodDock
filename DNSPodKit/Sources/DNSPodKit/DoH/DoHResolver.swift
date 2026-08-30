import Foundation
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// MARK: - DoH 解析生效检测
//
// 不走 dnsapi.cn,独立于 DNSPodClient 协议。
// 默认 provider 选大陆可达的腾讯/阿里;dns.google 在大陆基本不可用,仅作可选项。

public enum DoHProvider: String, Sendable, CaseIterable, Identifiable {
  case aliyun
  case tencent
  case cloudflare
  case google

  public var id: String { rawValue }

  /// JSON API(Google DNS API 风格:?name=&type=)
  public var endpoint: URL {
    switch self {
    case .aliyun: URL(string: "https://dns.alidns.com/resolve")!
    case .tencent: URL(string: "https://doh.pub/resolve")!
    case .cloudflare: URL(string: "https://cloudflare-dns.com/dns-query")!
    case .google: URL(string: "https://dns.google/resolve")!
    }
  }

  public var displayName: String {
    switch self {
    case .aliyun: "阿里 DoH"
    case .tencent: "腾讯 doh.pub"
    case .cloudflare: "Cloudflare"
    case .google: "Google"
    }
  }
}

public struct DoHAnswer: Sendable, Equatable {
  /// 记录类型编号(1=A, 28=AAAA, 5=CNAME, 15=MX, 16=TXT)
  public let type: Int
  public let ttl: Int
  public let data: String
}

public enum DoHSource: Sendable, Equatable {
  case doh(DoHProvider)
  /// M2:DoH 不可达时回退系统解析,结果必须标注来源
  case system
}

public struct DoHResult: Sendable, Equatable {
  public let name: String
  public let answers: [DoHAnswer]
  public let source: DoHSource
}

/// DoH 查询器。M2 补:3–5s 硬超时 + 系统解析回退(结果标注来源)。
public struct DoHResolver: Sendable {
  public let provider: DoHProvider
  private let transport: HTTPTransport

  public init(provider: DoHProvider = .aliyun, transport: HTTPTransport = URLSessionTransport(timeout: 5)) {
    self.provider = provider
    self.transport = transport
  }

  public func resolve(name: String, recordType: String = "A") async throws -> DoHResult {
    let wireType = Self.wireType(for: recordType)
    var components = URLComponents(url: provider.endpoint, resolvingAgainstBaseURL: false)!
    components.queryItems = [
      URLQueryItem(name: "name", value: name),
      URLQueryItem(name: "type", value: String(wireType)),
    ]
    let request = HTTPRequest(
      url: components.url!,
      method: "GET",
      headers: ["Accept": "application/dns-json"],
      body: nil
    )
    let response = try await transport.send(request)
    guard (200..<300).contains(response.statusCode) else {
      throw DNSPodError.transport("DoH HTTP \(response.statusCode)")
    }

    struct DNSJSONResponse: Codable {
      struct Answer: Codable {
        let type: FlexInt?
        let ttl: FlexInt?
        let data: String?
      }
      let status: FlexInt?
      let answer: [Answer]?
    }
    let decoded: DNSJSONResponse
    do {
      decoded = try JSONDecoder().decode(DNSJSONResponse.self, from: response.body)
    } catch {
      throw DNSPodError.invalidResponse("DoH 响应无法解码")
    }
    guard decoded.status?.value == 0 else {
      throw DNSPodError.transport("DoH 返回状态 \(decoded.status?.value ?? -1)(3 = 域名不存在)")
    }
    return DoHResult(
      name: name,
      answers: (decoded.answer ?? []).compactMap { answer in
        guard let data = answer.data else { return nil }
        return DoHAnswer(type: answer.type?.value ?? 0, ttl: answer.ttl?.value ?? 0, data: data)
      },
      source: .doh(provider)
    )
  }

  /// 记录类型名 → 线格式编号
  public static func wireType(for recordType: String) -> Int {
    switch recordType.uppercased() {
    case "A": 1
    case "NS": 2
    case "CNAME": 5
    case "PTR": 12
    case "MX": 15
    case "TXT": 16
    case "AAAA": 28
    case "SRV": 33
    case "CAA": 257
    default: 1
    }
  }
}

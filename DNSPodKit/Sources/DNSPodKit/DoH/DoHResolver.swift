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
    // SE-0461:非隔离 async 继承调用方 actor;DoH 往返与解码必须离开主线程
    let provider = self.provider
    let transport = self.transport
    return try await Task.detached(priority: .userInitiated) {
      try await Self.resolveOnCooperativePool(
        name: name, recordType: recordType, provider: provider, transport: transport)
    }.value
  }

  private static func resolveOnCooperativePool(
    name: String, recordType: String, provider: DoHProvider, transport: HTTPTransport
  ) async throws -> DoHResult {
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

  /// DoH 优先,失败回退系统解析(Apple 平台;结果必须标注来源)。
  /// 仅 A 记录可回退;其余类型直接抛 DoH 的原始错误。
  public func resolveWithFallback(name: String, recordType: String = "A") async throws -> DoHResult {
    do {
      return try await resolve(name: name, recordType: recordType)
    } catch {
      #if canImport(Darwin)
        if recordType.uppercased() == "A" {
          // getaddrinfo 是阻塞调用,同样必须离开主线程
          let addresses = await Task.detached(priority: .userInitiated) {
            SystemIPv4Resolver.resolve(name: name)
          }.value
          if !addresses.isEmpty {
            return DoHResult(
              name: name,
              answers: addresses.map { DoHAnswer(type: 1, ttl: 0, data: $0) },
              source: .system
            )
          }
        }
      #endif
      throw error
    }
  }
}

#if canImport(Darwin)
  import Darwin

  /// getaddrinfo 直查 A 记录(系统解析回退,Apple 平台)
  enum SystemIPv4Resolver {
    static func resolve(name: String) -> [String] {
      var hints = addrinfo()
      hints.ai_family = AF_INET
      var result: UnsafeMutablePointer<addrinfo>?
      guard getaddrinfo(name, nil, &hints, &result) == 0, let first = result else { return [] }
      defer { freeaddrinfo(result) }

      var addresses: [String] = []
      var node: UnsafeMutablePointer<addrinfo>? = first
      while let current = node {
        if current.pointee.ai_family == AF_INET, let sockaddrPtr = current.pointee.ai_addr {
          sockaddrPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
            var address = sin.pointee.sin_addr
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            if inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
              let chars = buffer.prefix { $0 != 0 }
              addresses.append(String(decoding: chars.lazy.map { UInt8(bitPattern: $0) }, as: UTF8.self))
            }
          }
        }
        node = current.pointee.ai_next
      }
      return addresses
    }
  }
#endif

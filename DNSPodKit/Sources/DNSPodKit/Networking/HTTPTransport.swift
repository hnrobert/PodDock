import Foundation
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// MARK: - 传输层
//
// 全 Kit 的测试支点:生产用 URLSessionTransport,测试/Preview 用 MockTransport,
// LegacyClient 只依赖 HTTPTransport 协议。

public struct HTTPRequest: Sendable {
  public let url: URL
  public let method: String
  public let headers: [String: String]
  public let body: Data?

  public init(url: URL, method: String = "POST", headers: [String: String] = [:], body: Data? = nil) {
    self.url = url
    self.method = method
    self.headers = headers
    self.body = body
  }
}

public struct HTTPResponse: Sendable {
  public let statusCode: Int
  public let body: Data
  public let headers: [String: String]

  public init(statusCode: Int, body: Data, headers: [String: String] = [:]) {
    self.statusCode = statusCode
    self.body = body
    self.headers = headers
  }

  /// 测试便利:以 JSON 字符串构造 200 响应
  public static func ok(_ json: String) -> HTTPResponse {
    HTTPResponse(statusCode: 200, body: Data(json.utf8))
  }
}

public protocol HTTPTransport: Sendable {
  func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// 生产传输。凭据会话必须不可落盘:ephemeral + 忽略本地缓存,
/// token 与记录数据不进 URLCache(DNSPod 的 t 开头回传 cookie 由
/// ephemeral session 的私有 cookie store 自动维持,替代旧仓库的手动逻辑)。
public final class URLSessionTransport: HTTPTransport {
  private let session: URLSession

  public init(timeout: TimeInterval = 30) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = timeout
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    session = URLSession(configuration: configuration)
  }

  public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
    var urlRequest = URLRequest(url: request.url)
    urlRequest.httpMethod = request.method
    urlRequest.httpBody = request.body
    for (name, value) in request.headers {
      urlRequest.setValue(value, forHTTPHeaderField: name)
    }
    let (data, response) = try await session.data(for: urlRequest)
    let httpResponse = response as? HTTPURLResponse
    return HTTPResponse(
      statusCode: httpResponse?.statusCode ?? 0,
      body: data,
      headers: httpResponse?.allHeaderFields.reduce(into: [String: String]()) {
        if let key = $1.key as? String { $0[key.lowercased()] = String(describing: $1.value) }
      } ?? [:]
    )
  }
}

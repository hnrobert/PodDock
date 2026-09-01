import Foundation
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// MARK: - Transport
//
// The Kit's test pivot: URLSessionTransport in production, MockTransport in tests/previews,
// LegacyClient depends only on the HTTPTransport protocol.

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

  /// Test convenience: 200 response from a JSON string
  public static func ok(_ json: String) -> HTTPResponse {
    HTTPResponse(statusCode: 200, body: Data(json.utf8))
  }
}

public protocol HTTPTransport: Sendable {
  func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// Production transport. Credential sessions must never touch disk: ephemeral + ignore local cache,
/// tokens and record data stay out of URLCache (DNSPod's t-prefixed cookies are kept by
/// the ephemeral session's private cookie store maintains them — replacing the old repo's manual logic).
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

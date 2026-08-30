import Foundation

/// 确定性 mock 传输:按序回放预置结果并记录全部请求。
/// 服务 DNSPodKit 单测与 App 的 SwiftUI Preview / XCUITest。
public actor MockTransport: HTTPTransport {
  private var queue: [Result<HTTPResponse, Error>] = []
  public private(set) var requests: [HTTPRequest] = []

  public init(_ results: [Result<HTTPResponse, Error>] = []) {
    self.queue = results
  }

  public func enqueue(_ result: Result<HTTPResponse, Error>) {
    queue.append(result)
  }

  public func enqueue(ok json: String) {
    queue.append(.success(HTTPResponse.ok(json)))
  }

  public func enqueue(error: Error) {
    queue.append(.failure(error))
  }

  public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
    requests.append(request)
    guard !queue.isEmpty else {
      throw DNSPodError.transport("MockTransport: 队列为空,收到 \(request.method) \(request.url.absoluteString)")
    }
    return try queue.removeFirst().get()
  }

  public func recordedFormBodies() -> [[String: String]] {
    requests.map { request in
      guard let body = request.body else { return [:] }
      return FormEncoder.decode(String(decoding: body, as: UTF8.self))
    }
  }

  public func reset() {
    queue.removeAll()
    requests.removeAll()
  }
}

import Testing
import Foundation
@testable import DNSPodKit

@Suite("RecordOptionsProvider 缓存语义")
struct RecordOptionsProviderTests {
  private func domain(_ grade: String = "DP_Free", id: String = "2317346") -> DNSDomain {
    DNSDomain(id: DomainID(id), name: "example.com", grade: grade, state: .enable, recordCount: 0, updatedOn: "")
  }

  @Test("同一 grade 的 type、同一 domain 的 line 只拉取一次")
  func cachesPerGradeAndDomain() async throws {
    let typeFetches = Counter()
    let lineFetches = Counter()
    let provider = RecordOptionsProvider(
      fetchTypes: { grade in
        await typeFetches.increment()
        return ["A", "CNAME"]
      },
      fetchLines: { _, _ in
        await lineFetches.increment()
        return ["默认", "电信"]
      })

    let d1 = domain()
    let d2 = domain(id: "9999999")  // 同 grade 不同域名
    _ = try await provider.options(for: d1)
    _ = try await provider.options(for: d1)
    _ = try await provider.options(for: d2)

    let typeCount = await typeFetches.count
    let lineCount = await lineFetches.count
    #expect(typeCount == 1)  // grade 相同 → type 只拉一次
    #expect(lineCount == 2)  // domain 不同 → line 各拉一次
  }

  @Test("不同 grade 的 type 分别拉取")
  func gradeIsolation() async throws {
    let fetches = Counter()
    let provider = RecordOptionsProvider(
      fetchTypes: { _ in
        await fetches.increment()
        return ["A"]
      },
      fetchLines: { _, _ in [] })

    _ = try await provider.options(for: domain("DP_Free"))
    _ = try await provider.options(for: domain("DP_Plus"))

    let count = await fetches.count
    #expect(count == 2)
  }

  @Test("reset 后重新拉取")
  func reset() async throws {
    let fetches = Counter()
    let provider = RecordOptionsProvider(
      fetchTypes: { _ in
        await fetches.increment()
        return ["A"]
      },
      fetchLines: { _, _ in [] })

    _ = try await provider.options(for: domain())
    await provider.reset()
    _ = try await provider.options(for: domain())

    let count = await fetches.count
    #expect(count == 2)
  }
}

/// 线程安全计数器
actor Counter {
  private(set) var count = 0
  func increment() {
    count += 1
  }
}

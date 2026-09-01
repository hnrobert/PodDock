import Testing
import Foundation
@testable import DNSPodKit

@Suite("RecordOptionsProvider caching semantics")
struct RecordOptionsProviderTests {
  private func domain(_ grade: String = "DP_Free", id: String = "2317346") -> DNSDomain {
    DNSDomain(id: DomainID(id), name: "example.com", grade: grade, state: .enable, recordCount: 0, updatedOn: "")
  }

  @Test("types fetched once per grade, lines once per domain")
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
    let d2 = domain(id: "9999999")  // same grade, different domain
    _ = try await provider.options(for: d1)
    _ = try await provider.options(for: d1)
    _ = try await provider.options(for: d2)

    let typeCount = await typeFetches.count
    let lineCount = await lineFetches.count
    #expect(typeCount == 1)  // same grade → type fetched once
    #expect(lineCount == 2)  // different domain → line fetched per domain
  }

  @Test("types fetched per distinct grade")
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

  @Test("refetches after reset")
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

/// Thread-safe counter
actor Counter {
  private(set) var count = 0
  func increment() {
    count += 1
  }
}

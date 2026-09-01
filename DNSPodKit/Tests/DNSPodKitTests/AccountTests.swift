import Testing
import Foundation
@testable import DNSPodKit

@Suite("Account model")
struct AccountTests {
  @Test("粘贴 \"ID,Token\" 自动拆分")
  func parsePasted() throws {
    let parsed = Account.parse(pasted: " 123456, aBcDeFgHiJkL ")
    let value = try #require(parsed)
    #expect(value.id == "123456")
    #expect(value.token == "aBcDeFgHiJkL")
  }

  @Test("rejects missing half, extra commas, empty input")
  func parseRejectsInvalid() {
    #expect(Account.parse(pasted: "123456") == nil)
    #expect(Account.parse(pasted: "123456,") == nil)
    #expect(Account.parse(pasted: ",token") == nil)
    #expect(Account.parse(pasted: "") == nil)
  }

  @Test("default label uses the last 4 of the Token ID")
  func defaultLabel() {
    #expect(Account.defaultLabel(tokenID: "123456") == "账户 3456")
    #expect(Account.defaultLabel(tokenID: "12") == "账户 12")
  }

  @Test("InMemoryAccountStore save/load/remove")
  func inMemoryStore() async throws {
    let store = InMemoryAccountStore()
    let account = Account(loginTokenID: "123", loginToken: "abc")
    try await store.save(account)

    let loaded = try await store.account(id: account.id)
    #expect(loaded == account)

    let listed = try await store.accounts()
    #expect(listed.count == 1)

    try await store.remove(id: account.id)
    let after = try await store.accounts()
    #expect(after.isEmpty)
  }
}

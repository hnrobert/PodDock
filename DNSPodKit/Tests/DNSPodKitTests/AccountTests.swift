import Testing
import Foundation
@testable import DNSPodKit

@Suite("账户模型")
struct AccountTests {
  @Test("粘贴 \"ID,Token\" 自动拆分")
  func parsePasted() throws {
    let parsed = Account.parse(pasted: " 123456, aBcDeFgHiJkL ")
    let value = try #require(parsed)
    #expect(value.id == "123456")
    #expect(value.token == "aBcDeFgHiJkL")
  }

  @Test("缺一半、多逗号、空串都拒绝")
  func parseRejectsInvalid() {
    #expect(Account.parse(pasted: "123456") == nil)
    #expect(Account.parse(pasted: "123456,") == nil)
    #expect(Account.parse(pasted: ",token") == nil)
    #expect(Account.parse(pasted: "") == nil)
  }

  @Test("默认标签取 Token ID 后 4 位")
  func defaultLabel() {
    #expect(Account.defaultLabel(tokenID: "123456") == "账户 3456")
    #expect(Account.defaultLabel(tokenID: "12") == "账户 12")
  }

  @Test("InMemoryAccountStore 增删查")
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

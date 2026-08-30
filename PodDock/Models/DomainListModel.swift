import Foundation
import DNSPodKit
import Observation

/// 域名列表模型:加载/搜索/启停/增删,错误就地呈现。
@MainActor
@Observable
final class DomainListModel {
  private weak var environment: AppEnvironment?

  private(set) var domains: [DNSDomain] = []
  private(set) var isLoading = false
  var errorMessage: String?
  var searchText = ""

  func attach(environment: AppEnvironment) {
    self.environment = environment
  }

  var filteredDomains: [DNSDomain] {
    let keyword = searchText.trimmingCharacters(in: .whitespaces).lowercased()
    guard !keyword.isEmpty else { return domains }
    return domains.filter { $0.name.lowercased().contains(keyword) }
  }

  func load() async {
    guard let client = environment?.client, !isLoading else { return }
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      domains = try await client.listDomains()
    } catch let error as DNSPodError {
      if error.isAuthenticationFailure, let environment {
        await environment.handleAuthenticationFailure()
      }
      errorMessage = describeError(error)
    } catch {
      errorMessage = describeError(error)
    }
  }

  func createDomain(name: String) async -> Bool {
    guard let client = environment?.client else { return false }
    do {
      try await client.createDomain(name: name)
      await load()
      return true
    } catch {
      errorMessage = describeError(error)
      return false
    }
  }

  func toggle(_ domain: DNSDomain) async {
    guard let client = environment?.client else { return }
    // pause → enable;enable → disable。spam/lock 不可切换(由视图层禁用)
    let target: ToggleStatus = domain.state == .enable ? .disable : .enable
    do {
      try await client.setDomainStatus(id: domain.id, to: target)
      await load()
    } catch {
      errorMessage = describeError(error)
    }
  }

  func remove(_ domain: DNSDomain) async {
    guard let client = environment?.client else { return }
    do {
      try await client.removeDomain(id: domain.id)
      domains.removeAll { $0.id == domain.id }
    } catch {
      errorMessage = describeError(error)
    }
  }
}

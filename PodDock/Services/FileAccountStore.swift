import Foundation
import DNSPodKit

/// File-based account store (Application Support/PodDock/accounts.json).
///
/// The macOS keychain scopes items by the app's code-signing identity, which changes on
/// every Xcode rebuild — accounts saved in one debug session vanish in the next.
/// A local file has no signing dependency and persists across all launch contexts
/// (Xcode, VS Code, Finder, CLI). Filesystem permissions protect it from other users;
/// for a personal-use DNS tool this is the right trade-off between reliability and security.
/// (iOS keeps the Keychain store — it has no signing churn there.)
final class FileAccountStore: AccountStoring, Sendable {
  private let fileURL: URL
  private let lock = NSLock()

  init(directory: URL? = nil) {
    let base =
      directory
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
      .appendingPathComponent("PodDock", isDirectory: true)
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    fileURL = base.appendingPathComponent("accounts.json")
  }

  // MARK: - Private I/O

  private func loadAll() -> [Account] {
    lock.lock()
    defer { lock.unlock() }
    guard let data = try? Data(contentsOf: fileURL),
      let accounts = try? JSONDecoder().decode([Account].self, from: data)
    else { return [] }
    return accounts
  }

  private func writeAll(_ accounts: [Account]) {
    lock.lock()
    defer { lock.unlock() }
    guard let data = try? JSONEncoder().encode(accounts) else { return }
    try? data.write(to: fileURL, options: .atomic)
  }

  // MARK: - AccountStoring

  func save(_ account: Account) async throws {
    var all = loadAll()
    all.removeAll { $0.id == account.id }
    all.append(account)
    writeAll(all)
  }

  func account(id: UUID) async throws -> Account? {
    loadAll().first { $0.id == id }
  }

  func accounts() async throws -> [Account] {
    loadAll().sorted { $0.createdAt < $1.createdAt }
  }

  func remove(id: UUID) async throws {
    var all = loadAll()
    all.removeAll { $0.id == id }
    writeAll(all)
  }
}

import SwiftUI
import DNSPodKit

/// Localized domain-state word. The sidebar shows it inline in the caption
/// line for non-active states; enabled rows carry no badge at all.
enum DomainStateText {
  static func label(for state: DomainState) -> String {
    let key: String
    switch state {
    case .enable: key = "Enabled"
    case .pause: key = "Paused"
    case .spam: key = "Banned"
    case .lock: key = "Locked"
    case .unknown: key = "Unknown"
    }
    return NSLocalizedString(key, comment: "domain state")
  }
}

/// Record enable/pause dot
struct RecordStateDot: View {
  let isEnabled: Bool

  var body: some View {
    Circle()
      .fill(isEnabled ? Color.green : Color.gray.opacity(0.5))
      .frame(width: 8, height: 8)
      .help(isEnabled ? "Enabled" : "Paused")
  }
}

import SwiftUI
import DNSPodKit

/// 域名状态徽章(品牌绿点缀:启用态用强调色)
struct StatusBadge: View {
  let state: DomainState

  var body: some View {
    Text(NSLocalizedString(label, comment: "domain state badge"))
      .font(.caption.weight(.medium))
      .padding(.horizontal, 8)
      .padding(.vertical, 2)
      .background(tint.opacity(0.12), in: Capsule())
      .foregroundStyle(tint)
  }

  private var label: String {
    switch state {
    case .enable: "Enabled"
    case .pause: "Paused"
    case .spam: "Banned"
    case .lock: "Locked"
    case .unknown: "Unknown"
    }
  }

  private var tint: Color {
    switch state {
    case .enable: .green
    case .pause: .orange
    case .spam: .red
    case .lock: .gray
    case .unknown: .secondary
    }
  }
}

/// 记录启停小圆点
struct RecordStateDot: View {
  let isEnabled: Bool

  var body: some View {
    Circle()
      .fill(isEnabled ? Color.green : Color.gray.opacity(0.5))
      .frame(width: 8, height: 8)
      .help(isEnabled ? "Enabled" : "Paused")
  }
}

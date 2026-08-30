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
    case .enable: "启用"
    case .pause: "暂停"
    case .spam: "封禁"
    case .lock: "锁定"
    case .unknown: "未知"
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
      .help(isEnabled ? "已启用" : "已暂停")
  }
}

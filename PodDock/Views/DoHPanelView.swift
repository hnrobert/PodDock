import SwiftUI
import DNSPodKit

/// DoH 生效检测:多 provider,可回退系统解析(结果标注来源)。
struct DoHPanelView: View {
  @Environment(AppEnvironment.self) private var environment
  @Environment(\.dismiss) private var dismiss

  @State var initialName: String
  @State private var recordType = "A"
  @State private var provider: DoHProvider = .aliyun
  @State private var isRunning = false
  @State private var result: DoHResult?
  @State private var errorMessage: String?

  var body: some View {
    VStack(spacing: 16) {
      Text("解析生效检测").font(.headline)

      Form {
        TextField("主机名", text: $initialName, prompt: Text("完整主机名,如 www.example.com"))
          .textFieldStyle(.roundedBorder)
          .onSubmit(run)
        HStack {
          Picker("记录类型", selection: $recordType) {
            ForEach(["A", "AAAA", "CNAME", "MX", "TXT"], id: \.self) { Text($0) }
          }
          .frame(maxWidth: 120)
          Picker("服务商", selection: $provider) {
            ForEach(DoHProvider.allCases) { provider in
              Text(provider.displayName).tag(provider)
            }
          }
          .frame(maxWidth: 160)
        }
      }
      .frame(maxWidth: 420)

      HStack {
        Button {
          run()
        } label: {
          if isRunning {
            ProgressView().controlSize(.small)
          } else {
            Text("查询")
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(initialName.isEmpty || isRunning)
        Button("完成") { dismiss() }
      }

      if let errorMessage {
        Text(errorMessage).font(.callout).foregroundStyle(.red)
      }

      if let result {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Label(sourceLabel(result.source), systemImage: sourceIcon(result.source))
              .font(.caption)
              .foregroundStyle(.secondary)
            Spacer()
          }
          if result.answers.isEmpty {
            Text("没有查询到记录——可能尚未生效或类型不符。")
              .foregroundStyle(.secondary)
          }
          ForEach(Array(result.answers.enumerated()), id: \.offset) { _, answer in
            HStack {
              Text(answer.data).font(.system(.body, design: .monospaced)).textSelection(.enabled)
              Spacer()
              Text("TTL \(answer.ttl)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
            .accessibilityIdentifier("doh-answer")
          }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: 460, alignment: .leading)
      }

      Spacer()
    }
    .padding(24)
    .frame(minWidth: 520, minHeight: 440)
  }

  private func run() {
    Task {
      isRunning = true
      defer { isRunning = false }
      result = nil
      errorMessage = nil
      let resolver = DoHResolver(provider: provider)
      do {
        result = try await resolver.resolveWithFallback(name: initialName, recordType: recordType)
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  private func sourceLabel(_ source: DoHSource) -> String {
    switch source {
    case .doh(let provider): "来源:\(provider.displayName)"
    case .system: "来源:系统解析(DoH 不可达时回退)"
    }
  }

  private func sourceIcon(_ source: DoHSource) -> String {
    switch source {
    case .doh: "network"
    case .system: "arrow.triangle.branch"
    }
  }
}

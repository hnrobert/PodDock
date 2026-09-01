import SwiftUI
import DNSPodKit

/// DoH propagation check: multiple providers with system fallback (labeled source).
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
      Text("Propagation Check").font(.headline)

      Form {
        TextField("Hostname", text: $initialName, prompt: Text("Full hostname, e.g. www.example.com"))
          .textFieldStyle(.roundedBorder)
          .onSubmit(run)
        HStack {
          Picker("Record Type", selection: $recordType) {
            ForEach(["A", "AAAA", "CNAME", "MX", "TXT"], id: \.self) { Text($0) }
          }
          .frame(maxWidth: 120)
          Picker("Provider", selection: $provider) {
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
            Text("Query")
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(initialName.isEmpty || isRunning)
        Button("Done") { dismiss() }
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
            Text("No answers — the change may not be live yet, or the type differs.")
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
        errorMessage = describeError(error)
      }
    }
  }

  private func sourceLabel(_ source: DoHSource) -> String {
    switch source {
    case .doh(let provider):
      String(localized: "Source: \(provider.displayName)")
    case .system:
      String(localized: "Source: system resolver (DoH unreachable)")
    }
  }

  private func sourceIcon(_ source: DoHSource) -> String {
    switch source {
    case .doh: "network"
    case .system: "arrow.triangle.branch"
    }
  }
}

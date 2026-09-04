import SwiftUI
import DNSPodKit

/// Fixed check target: hostname + record type come from the record that launched the panel.
struct DoHTarget: Identifiable {
  let hostname: String
  let recordType: String

  var id: String { "\(recordType)/\(hostname)" }
}

/// DoH propagation check. The target is fixed by the source record; the only
/// choice is the provider. Query runs on open and again when the provider changes.
struct DoHPanelView: View {
  @Environment(\.dismiss) private var dismiss

  let target: DoHTarget
  @State private var provider: DoHProvider = .aliyun
  @State private var runID = UUID()
  @State private var isRunning = false
  @State private var result: DoHResult?
  @State private var errorMessage: String?

  var body: some View {
    VStack(spacing: 16) {
      Text("Propagation Check").font(.headline)

      // Read-only target context — the record the user right-clicked
      HStack(spacing: 10) {
        Text(target.hostname)
          .font(.system(.title3, design: .monospaced))
          .textSelection(.enabled)
        Text(target.recordType)
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(.quaternary, in: Capsule())
      }

      HStack {
        Picker("Provider", selection: $provider) {
          ForEach(DoHProvider.allCases) { provider in
            Text(provider.displayName).tag(provider)
          }
        }
        .frame(maxWidth: 180)

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
        .disabled(isRunning)
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
    .frame(minWidth: 520, minHeight: 400)
    .task { run() }
    .onChange(of: provider) { _, _ in run() }
  }

  /// Runs a query; stale completions (provider switched mid-flight) no-op via runID,
  /// so they never overwrite the latest run's state or clear its spinner.
  private func run() {
    let id = UUID()
    runID = id
    isRunning = true
    result = nil
    errorMessage = nil
    let resolver = DoHResolver(provider: provider)
    Task {
      do {
        let outcome = try await resolver.resolveWithFallback(
          name: target.hostname, recordType: target.recordType)
        guard runID == id else { return }
        result = outcome
        isRunning = false
      } catch {
        guard runID == id else { return }
        errorMessage = describeError(error)
        isRunning = false
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

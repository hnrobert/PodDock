import SwiftUI
import DNSPodKit

/// LLM 助手面板:对话式,自然语言直接操作解析;写操作经确认门。
struct AssistantView: View {
  @Environment(AppEnvironment.self) private var environment
  @State private var draft = ""

  private var model: AssistantModel { environment.assistant }

  var body: some View {
    VStack(spacing: 0) {
      transcriptView

      Divider()

      HStack(spacing: 10) {
        TextField("Ask anything about your DNS…", text: $draft, axis: .vertical)
          .textFieldStyle(.roundedBorder)
          .lineLimit(1...4)
          .onSubmit(send)
        Button(action: send) {
          if model.isRunning {
            ProgressView().controlSize(.small)
          } else {
            Image(systemName: "arrow.up.circle.fill").font(.title2)
          }
        }
        .buttonStyle(.plain)
        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isRunning)
        .keyboardShortcut(.return, modifiers: [])
      }
      .padding(12)
    }
    .frame(minWidth: 460, minHeight: 480)
    .navigationTitle("Assistant")
    .toolbar {
      ToolbarItem(placement: .automatic) {
        Button("Clear") { model.clear() }
          .disabled(model.transcript.isEmpty)
      }
    }
    .confirmationDialog(
      model.pendingConfirmation.map { "\($0.toolName)" } ?? "",
      isPresented: Binding(
        get: { model.pendingConfirmation != nil },
        set: { if !$0 && model.pendingConfirmation != nil { model.confirmPending(false) } }
      ),
      titleVisibility: .visible
    ) {
      Button("Allow \(model.pendingConfirmation?.toolName ?? "")", role: .destructive) {
        model.confirmPending(true)
      }
      Button("Decline", role: .cancel) {
        model.confirmPending(false)
      }
    } message: {
      Text(model.pendingConfirmation?.summary ?? "")
    }
  }

  private var transcriptView: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 10) {
          if model.transcript.isEmpty {
            ContentUnavailableView(
              "DNS Assistant",
              systemImage: "sparkles",
              description: Text("Try: “list my domains” or “point www of example.com to 1.2.3.4”")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
          }
          ForEach(model.transcript) { entry in
            AssistantEntryView(entry: entry)
              .id(entry.id)
          }
        }
        .padding(14)
      }
      .onChange(of: model.transcript.last?.id) { _, last in
        if let last { proxy.scrollTo(last, anchor: .bottom) }
      }
    }
  }

  private func send() {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !model.isRunning else { return }
    draft = ""
    Task { await model.send(text) }
  }
}

private struct AssistantEntryView: View {
  let entry: AssistantModel.Entry

  var body: some View {
    switch entry {
    case .user(let text):
      bubble(text, icon: "person.fill", tint: .accentColor, alignRight: true)
    case .assistant(let text):
      bubble(text, icon: "sparkles", tint: .green, alignRight: false)
    case .tool(let name, let summary, let isPending):
      HStack(spacing: 8) {
        if isPending {
          ProgressView().controlSize(.mini)
        } else {
          Image(systemName: "wrench.and.screwdriver").font(.caption)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(name).font(.caption.monospaced().weight(.semibold)).foregroundStyle(.secondary)
          Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(3)
        }
        Spacer()
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    case .error(let text):
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        Text(text).font(.callout)
      }
      .padding(10)
      .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
  }

  private func bubble(_ text: String, icon: String, tint: Color, alignRight: Bool) -> some View {
    HStack(alignment: .top, spacing: 8) {
      if alignRight { Spacer(minLength: 32) }
      VStack(alignment: alignRight ? .trailing : .leading, spacing: 4) {
        Label(icon, systemImage: icon).font(.caption2).foregroundStyle(tint)
        Text(text)
          .textSelection(.enabled)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
      }
      if !alignRight { Spacer(minLength: 32) }
    }
  }
}

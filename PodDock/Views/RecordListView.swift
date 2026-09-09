import SwiftUI
import DNSPodKit
#if canImport(AppKit)
  import AppKit
#endif

/// Record list: search/type filter/sort/multi-select batch (sequential + throttled)/quick remark/toggle/remove (confirmed).
struct RecordListView: View {
  @Environment(AppEnvironment.self) private var environment
  let domain: DNSDomain

  @State private var model = RecordListModel()
  @State private var selection = Set<RecordID>()
  @State private var isSelecting = false

  @State private var isShowingCreate = false
  @State private var editingRecord: DNSRecord?
  @State private var remarkRecord: DNSRecord?
  @State private var remarkDraft = ""
  @State private var isShowingAssistant = false
  @State private var doHTarget: DoHTarget?
  @State private var pendingDelete: DNSRecord?
  @State private var pendingBatchDelete: [DNSRecord]?

  var body: some View {
    listPane
      .task(id: domain.id) {
        model.attach(environment: environment, domain: domain)
        selection.removeAll()  // stale RecordIDs from the previous domain
        await model.load()
        #if DEBUG
          FileHandle.standardError.write(Data("[PodDock] RecordListView loaded \(model.records.count) records for \(domain.name)\n".utf8))
        #endif
      }
      .sheet(isPresented: $isShowingCreate) {
        RecordFormView(mode: .create(domain: domain)) {
          Task { await model.load() }
        }
      }
      .sheet(item: $editingRecord) { record in
        RecordFormView(mode: .edit(domain: domain, record: record)) {
          Task { await model.load() }
        }
      }
      .sheet(item: $remarkRecord) { record in
        remarkSheet(record)
      }
      .sheet(item: $doHTarget) { target in
        DoHPanelView(target: target)
      }
      .sheet(isPresented: $isShowingAssistant) {
        AssistantView()
          .environment(environment)
      }
      .modifier(RecordDialogsLayer(
        pendingDelete: $pendingDelete,
        pendingBatchDelete: $pendingBatchDelete,
        remove: { record in Task { await model.remove(record) } },
        batchRemove: { records in
          Task { await model.batch(records, action: .remove); selection.removeAll() }
        }
      ))
      .modifier(RecordAlertsLayer(model: model))
  }

  /// List pane (List + overlay + nav + toolbar + filter bar) — split out to avoid type-check timeouts
  private var listPane: some View {
    // Native List selection: the system draws the rounded-capsule highlight.
    // The tap gestures below keep the selection set reliably populated
    // (plain click selects; cmd/shift toggles for batch mode).
    List(selection: $selection) {
      ForEach(model.filteredRecords) { record in
        recordRow(record)
      }
    }
    .overlay {
      if model.isLoading && model.records.isEmpty {
        ProgressView()
      } else if model.records.isEmpty {
        ContentUnavailableView(
          "No Records",
          systemImage: "list.bullet.rectangle",
          description: Text("Use + in the toolbar to add the first record")
        )
      }
    }
    .navigationTitle(domain.name)
    .searchable(
      text: Binding(get: { model.searchText }, set: { model.searchText = $0 }),
      prompt: "Search host / value / remark"
    )
    .toolbar { recordToolbar }
    .safeAreaInset(edge: .top) {
      filterBar
    }
  }

  private func recordRow(_ record: DNSRecord) -> some View {
    RecordRowView(record: record) {
      Task { await model.toggle(record) }
    }
    .tag(record.id)
    // Double-click opens the edit sheet; single click selects the row.
    // contentShape covers the whole row; gestures run simultaneously so the
    // List (multi-select in Select mode) keeps its own handling.
    .contentShape(.rect)
    .simultaneousGesture(TapGesture(count: 2).onEnded { editingRecord = record })
    .simultaneousGesture(TapGesture(count: 1).onEnded {
      // Plain click selects just this row; cmd/shift-click toggles membership
      // (multi-select works even where the List's own click handling doesn't)
      #if os(macOS)
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.shift) {
          if selection.contains(record.id) { selection.remove(record.id) } else { selection.insert(record.id) }
          return
        }
      #endif
      selection = [record.id]
    })
    .contextMenu {
      Button("Copy Value") { copyToPasteboard(record.value) }
      Button("Edit…") { editingRecord = record }
      Button("Remark…") {
        remarkRecord = record
        remarkDraft = record.remark
      }
      Button(record.isEnabled ? "Pause" : "Enable") {
        Task { await model.toggle(record) }
      }
      Divider()
      Button("Check via DoH") {
        let hostname = record.name == "@"
          ? model.domain?.name ?? domain.name
          : "\(record.name).\(domain.name)"
        doHTarget = DoHTarget(hostname: hostname, recordType: record.type)
      }
      Button("Remove…", role: .destructive) { pendingDelete = record }
    }
  }

  @ToolbarContentBuilder
  private var recordToolbar: some ToolbarContent {
    // The toolbar must be fully static: dynamic ToolbarItems / a Toggle inside the toolbar
    // crashes when NSToolbar inserts items (crash report: _insertNewItemWithItemIdentifier)
    ToolbarItem(placement: .primaryAction) {
      Button {
        isShowingCreate = true
      } label: {
        Label("Add Record", systemImage: "plus")
      }
    }
    ToolbarItem(placement: .automatic) {
      Button {
        Task { await model.load() }
      } label: {
        Label("Refresh", systemImage: "arrow.clockwise")
      }
    }
    ToolbarItem(placement: .automatic) {
      Button {
        isSelecting.toggle()
        if !isSelecting { selection.removeAll() }
      } label: {
        Label(
          isSelecting ? "Done Selecting" : "Select",
          systemImage: isSelecting ? "checkmark.circle.fill" : "checkmark.circle"
        )
      }
    }
    ToolbarItem(placement: .automatic) {
      Button {
        isShowingAssistant = true
      } label: {
        Label("Assistant", systemImage: "sparkles")
      }
    }
  }

  /// Type filter + sort bar (batch buttons live here too, keeping toolbar items static)
  private var filterBar: some View {
    HStack(spacing: 12) {
      Picker("Type", selection: Binding(
        get: { model.typeFilter },
        set: { model.typeFilter = $0 }
      )) {
        Text("All Types").tag(String?.none)
        ForEach(model.availableTypes, id: \.self) { type in
          Text(type).tag(String?.some(type))
        }
      }
      .frame(maxWidth: 160)

      Picker("Sort", selection: Binding(
        get: { model.sortOrder },
        set: { model.sortOrder = $0 }
      )) {
        ForEach(RecordListModel.SortOrder.allCases) { order in
          Text(order.displayName).tag(order)
        }
      }
      .frame(maxWidth: 140)

      Spacer()
      if model.isBatchRunning {
        ProgressView().controlSize(.small)
        Text("Batch running…").font(.caption).foregroundStyle(.secondary)
      } else if isSelecting {
        Button("Enable Selected (\(selection.count))") {
          let targets = model.records.filter { selection.contains($0.id) }
          Task { await model.batch(targets, action: .enable); selection.removeAll() }
        }
        .disabled(selection.isEmpty)
        Button("Pause Selected (\(selection.count))") {
          let targets = model.records.filter { selection.contains($0.id) }
          Task { await model.batch(targets, action: .disable); selection.removeAll() }
        }
        .disabled(selection.isEmpty)
        Button("Remove Selected (\(selection.count))…", role: .destructive) {
          pendingBatchDelete = model.records.filter { selection.contains($0.id) }
        }
        .disabled(selection.isEmpty)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(.bar)
  }

  private func remarkSheet(_ record: DNSRecord) -> some View {
    VStack(spacing: 14) {
      Text("Remark - \(record.name)").font(.headline)
      TextField("Remark", text: $remarkDraft, prompt: Text("Remark text (empty to clear)"))
        .textFieldStyle(.roundedBorder)
      HStack {
        Button("Cancel") { remarkRecord = nil }
        Button("Save") {
          let target = record
          let text = remarkDraft
          remarkRecord = nil
          Task { await model.setRemark(text, for: target) }
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(20)
    .frame(minWidth: 380, minHeight: 140)
  }
}

private struct RecordRowView: View {
  let record: DNSRecord
  let onToggle: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      RecordStateDot(isEnabled: record.isEnabled)
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(record.name).font(.body.weight(.medium))
          Text(record.type)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
          Text(record.line).font(.caption).foregroundStyle(.secondary)
        }
        // No .textSelection here: selectable text swallows clicks and breaks
        // row selection on macOS — copying lives in the context menu instead
        Text(record.value).font(.callout).foregroundStyle(.secondary)
        if !record.remark.isEmpty {
          Text("Remark: \(record.remark)").font(.caption).foregroundStyle(.tertiary)
        }
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 2) {
        Text("TTL \(record.ttl)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        if let weight = record.weight {
          Text("W \(weight)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        if record.type == "MX" {
          Text("MX \(record.mx)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
      }
      Toggle("", isOn: Binding(
        get: { record.isEnabled },
        set: { _ in onToggle() }
      ))
      .toggleStyle(.switch)
      .labelsHidden()
      .disabled(record.type == "NS")
      .help(record.isEnabled ? "Click to pause" : "Click to enable")
    }
    .padding(.vertical, 2)
    .accessibilityIdentifier("record-row-\(record.id.rawValue)")
  }
}

/// Removal confirmations (single + batch)
private struct RecordDialogsLayer: ViewModifier {
  @Binding var pendingDelete: DNSRecord?
  @Binding var pendingBatchDelete: [DNSRecord]?
  let remove: (DNSRecord) -> Void
  let batchRemove: ([DNSRecord]) -> Void

  func body(content: Content) -> some View {
    content
      .confirmationDialog(
        "Remove Record",
        isPresented: Binding(
          get: { pendingDelete != nil },
          set: { if !$0 { pendingDelete = nil } }
        ),
        titleVisibility: .visible
      ) {
        Button("Remove \(pendingDelete?.name ?? "")", role: .destructive) {
          if let record = pendingDelete {
            remove(record)
          }
          pendingDelete = nil
        }
      } message: {
        Text("Records stop resolving immediately. This cannot be undone.")
      }
      .confirmationDialog(
        "Remove \(pendingBatchDelete?.count ?? 0) Records",
        isPresented: Binding(
          get: { pendingBatchDelete != nil },
          set: { if !$0 { pendingBatchDelete = nil } }
        ),
        titleVisibility: .visible
      ) {
        Button("Remove All", role: .destructive) {
          if let records = pendingBatchDelete {
            batchRemove(records)
          }
          pendingBatchDelete = nil
        }
      } message: {
        Text("Records will be removed one by one; failures are listed when done.")
      }
  }
}

/// Notice/error alerts bound to model messages
@MainActor
private struct RecordAlertsLayer: ViewModifier {
  let model: RecordListModel

  func body(content: Content) -> some View {
    content
      .alert(
        "Notice",
        isPresented: Binding(
          get: { model.latestMessage != nil },
          set: { if !$0 { model.latestMessage = nil } }
        )
      ) {
        Button("OK", role: .cancel) { model.latestMessage = nil }
      } message: {
        Text(model.latestMessage ?? "")
      }
      .alert(
        "Error",
        isPresented: Binding(
          get: { model.errorMessage != nil },
          set: { if !$0 { model.errorMessage = nil } }
        )
      ) {
        Button("OK", role: .cancel) { model.errorMessage = nil }
      } message: {
        Text(model.errorMessage ?? "")
      }
  }
}

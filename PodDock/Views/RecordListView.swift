import SwiftUI
import DNSPodKit

/// 记录列表:搜索/类型筛选/排序/多选批量(顺序+节流)/备注快编/启停/删除(确认框)。
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
  @State private var isShowingDoH = false
  @State private var doHName = ""
  @State private var pendingDelete: DNSRecord?
  @State private var pendingBatchDelete: [DNSRecord]?

  var body: some View {
    listPane
      .task(id: domain.id) {
        model.attach(environment: environment, domain: domain)
        await model.load()
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
      .sheet(isPresented: $isShowingDoH) {
        DoHPanelView(initialName: doHName)
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

  /// 列表面板(List + overlay + 导航 + 工具栏 + 筛选条)——拆出来防表达式超时
  private var listPane: some View {
    List(selection: isSelecting ? $selection : .constant(Set<RecordID>())) {
      ForEach(model.filteredRecords) { record in
        recordRow(record)
      }
    }
    .overlay {
      if model.isLoading && model.records.isEmpty {
        ProgressView()
      } else if model.records.isEmpty {
        ContentUnavailableView(
          "暂无解析记录",
          systemImage: "list.bullet.rectangle",
          description: Text("点击工具栏 + 添加第一条记录")
        )
      }
    }
    .navigationTitle(domain.name)
    .searchable(
      text: Binding(get: { model.searchText }, set: { model.searchText = $0 }),
      prompt: "搜索主机/值/备注"
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
    .contextMenu {
      Button("编辑…") { editingRecord = record }
      Button("备注…") {
        remarkRecord = record
        remarkDraft = record.remark
      }
      Button(record.isEnabled ? "暂停" : "启用") {
        Task { await model.toggle(record) }
      }
      Divider()
      Button("DoH 检测") {
        doHName = record.name == "@"
          ? model.domain?.name ?? domain.name
          : "\(record.name).\(domain.name)"
        isShowingDoH = true
      }
      Button("删除…", role: .destructive) { pendingDelete = record }
    }
  }

  @ToolbarContentBuilder
  private var recordToolbar: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
      Button {
        isShowingCreate = true
      } label: {
        Label("添加记录", systemImage: "plus")
      }
    }
    ToolbarItem(placement: .automatic) {
      Button {
        Task { await model.load() }
      } label: {
        Label("刷新", systemImage: "arrow.clockwise")
      }
    }
    ToolbarItem(placement: .automatic) {
      Toggle(isOn: $isSelecting) {
        Label("选择", systemImage: "checkmark.circle")
      }
      .toggleStyle(.button)
    }
    if isSelecting && !selection.isEmpty {
      ToolbarItemGroup(placement: .automatic) {
        Button("启用所选(\(selection.count))") {
          let targets = model.records.filter { selection.contains($0.id) }
          Task { await model.batch(targets, action: .enable); selection.removeAll() }
        }
        Button("暂停所选(\(selection.count))") {
          let targets = model.records.filter { selection.contains($0.id) }
          Task { await model.batch(targets, action: .disable); selection.removeAll() }
        }
        Button("删除所选(\(selection.count))…", role: .destructive) {
          pendingBatchDelete = model.records.filter { selection.contains($0.id) }
        }
      }
    }
  }

  /// 类型筛选 + 排序条
  private var filterBar: some View {
    HStack(spacing: 12) {
      Picker("类型", selection: Binding(
        get: { model.typeFilter },
        set: { model.typeFilter = $0 }
      )) {
        Text("全部类型").tag(String?.none)
        ForEach(model.availableTypes, id: \.self) { type in
          Text(type).tag(String?.some(type))
        }
      }
      .frame(maxWidth: 160)

      Picker("排序", selection: Binding(
        get: { model.sortOrder },
        set: { model.sortOrder = $0 }
      )) {
        ForEach(RecordListModel.SortOrder.allCases) { order in
          Text(order.rawValue).tag(order)
        }
      }
      .frame(maxWidth: 140)

      Spacer()
      if model.isBatchRunning {
        ProgressView().controlSize(.small)
        Text("批量执行中…").font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(.bar)
  }

  private func remarkSheet(_ record: DNSRecord) -> some View {
    VStack(spacing: 14) {
      Text("备注 - \(record.name)").font(.headline)
      TextField("备注内容(留空即清除)", text: $remarkDraft)
        .textFieldStyle(.roundedBorder)
      HStack {
        Button("取消") { remarkRecord = nil }
        Button("保存") {
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
        Text(record.value).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
        if !record.remark.isEmpty {
          Text("备注:\(record.remark)").font(.caption).foregroundStyle(.tertiary)
        }
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 2) {
        Text("TTL \(record.ttl)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
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
      .help(record.isEnabled ? "点击暂停" : "点击启用")
    }
    .padding(.vertical, 2)
    .accessibilityIdentifier("record-row-\(record.id.rawValue)")
  }
}

/// 删除确认(单条 + 批量)
private struct RecordDialogsLayer: ViewModifier {
  @Binding var pendingDelete: DNSRecord?
  @Binding var pendingBatchDelete: [DNSRecord]?
  let remove: (DNSRecord) -> Void
  let batchRemove: ([DNSRecord]) -> Void

  func body(content: Content) -> some View {
    content
      .confirmationDialog(
        "删除记录",
        isPresented: Binding(
          get: { pendingDelete != nil },
          set: { if !$0 { pendingDelete = nil } }
        ),
        titleVisibility: .visible
      ) {
        Button("删除 \(pendingDelete?.name ?? "")", role: .destructive) {
          if let record = pendingDelete {
            remove(record)
          }
          pendingDelete = nil
        }
      } message: {
        Text("删除后解析立即失效,不可恢复。")
      }
      .confirmationDialog(
        "批量删除 \(pendingBatchDelete?.count ?? 0) 条记录",
        isPresented: Binding(
          get: { pendingBatchDelete != nil },
          set: { if !$0 { pendingBatchDelete = nil } }
        ),
        titleVisibility: .visible
      ) {
        Button("全部删除", role: .destructive) {
          if let records = pendingBatchDelete {
            batchRemove(records)
          }
          pendingBatchDelete = nil
        }
      } message: {
        Text("将顺序删除所选记录,失败项会在完成后逐条列出。")
      }
  }
}

/// 提示与错误 alert(绑定模型消息)
@MainActor
private struct RecordAlertsLayer: ViewModifier {
  let model: RecordListModel

  func body(content: Content) -> some View {
    content
      .alert(
        "提示",
        isPresented: Binding(
          get: { model.latestMessage != nil },
          set: { if !$0 { model.latestMessage = nil } }
        )
      ) {
        Button("好", role: .cancel) { model.latestMessage = nil }
      } message: {
        Text(model.latestMessage ?? "")
      }
      .alert(
        "出错了",
        isPresented: Binding(
          get: { model.errorMessage != nil },
          set: { if !$0 { model.errorMessage = nil } }
        )
      ) {
        Button("好", role: .cancel) { model.errorMessage = nil }
      } message: {
        Text(model.errorMessage ?? "")
      }
  }
}

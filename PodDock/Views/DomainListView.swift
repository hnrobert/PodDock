import SwiftUI
import DNSPodKit

/// 侧栏域名列表:搜索/启停/添加/删除(确认框);spam/lock 不可切换。
struct DomainListView: View {
  @Environment(AppEnvironment.self) private var environment
  @Binding var selection: DomainID?

  @State private var isShowingAdd = false
  @State private var pendingDelete: DNSDomain?

  private var model: DomainListModel { environment.domains }

  var body: some View {
    List(selection: $selection) {
      ForEach(model.filteredDomains) { domain in
        DomainRowView(domain: domain) {
          Task { await model.toggle(domain) }
        }
        .tag(domain.id)
        .contextMenu {
          Button(domain.state == .enable ? "Pause DNS" : "Resume DNS") {
            Task { await model.toggle(domain) }
          }
          .disabled(domain.state == .spam || domain.state == .lock || domain.state == .unknown)
          Divider()
          Button("Remove Domain…", role: .destructive) {
            pendingDelete = domain
          }
        }
      }
    }
    .overlay {
      if model.domains.isEmpty && !model.isLoading {
        ContentUnavailableView.search(text: model.searchText)
      } else if model.isLoading && model.domains.isEmpty {
        ProgressView()
      }
    }
    .navigationTitle("Domains")
    .searchable(text: Binding(
      get: { model.searchText },
      set: { model.searchText = $0 }
    ), prompt: "Search domains")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          isShowingAdd = true
        } label: {
          Label("Add Domain", systemImage: "plus")
        }
      }
      ToolbarItem(placement: .automatic) {
        Button {
          Task { await model.load() }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
      }
    }
    .sheet(isPresented: $isShowingAdd) {
      AddDomainSheet()
    }
    .alert("Remove Domain", isPresented: Binding(
      get: { pendingDelete != nil },
      set: { if !$0 { pendingDelete = nil } }
    )) {
      Button("Remove", role: .destructive) {
        if let domain = pendingDelete {
          Task { await model.remove(domain) }
        }
        pendingDelete = nil
      }
      Button("Cancel", role: .cancel) { pendingDelete = nil }
    } message: {
      Text("Remove \(pendingDelete?.name ?? "")? Its records will stop resolving.")
    }
    .alert("Error", isPresented: Binding(
      get: { model.errorMessage != nil },
      set: { if !$0 { model.errorMessage = nil } }
    )) {
      Button("OK", role: .cancel) { model.errorMessage = nil }
    } message: {
      Text(model.errorMessage ?? "")
    }
  }
}

private struct DomainRowView: View {
  let domain: DNSDomain
  let onToggle: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        Text(domain.name).font(.body.weight(.medium)).textSelection(.enabled)
        HStack(spacing: 8) {
          Text("\(domain.recordCount) records")
          Text(domain.grade).foregroundStyle(.secondary)
          if !domain.updatedOn.isEmpty {
            Text(domain.updatedOn).foregroundStyle(.tertiary)
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      Spacer()
      StatusBadge(state: domain.state)
      // 行内开关(spam/lock/unknown 禁用)
      Toggle("", isOn: Binding(
        get: { domain.state == .enable },
        set: { _ in onToggle() }
      ))
      .toggleStyle(.switch)
      .labelsHidden()
      .disabled(domain.state == .spam || domain.state == .lock || domain.state == .unknown)
      .help(domain.state == .enable ? "Click to pause" : "Click to enable")
    }
    .padding(.vertical, 2)
    .accessibilityIdentifier("domain-row-\(domain.id.rawValue)")
  }
}

/// 添加域名
struct AddDomainSheet: View {
  @Environment(AppEnvironment.self) private var environment
  @Environment(\.dismiss) private var dismiss

  @State private var name = ""
  @State private var isWorking = false
  @State private var errorMessage: String?

  var body: some View {
    VStack(spacing: 16) {
      Text("Add Domain").font(.headline)
      TextField("Domain", text: $name, prompt: Text("example.com"))
        .textFieldStyle(.roundedBorder)
        .onSubmit(submit)
      if let errorMessage {
        Text(errorMessage).font(.callout).foregroundStyle(.red)
      }
      HStack {
        Button("Cancel") { dismiss() }
        Button("Add", action: submit)
          .buttonStyle(.borderedProminent)
          .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
      }
    }
    .padding(20)
    .frame(minWidth: 360)
  }

  private func submit() {
    Task {
      isWorking = true
      defer { isWorking = false }
      let trimmed = name.trimmingCharacters(in: .whitespaces)
      let ok = await environment.domains.createDomain(name: trimmed)
      if ok {
        dismiss()
      } else {
        errorMessage = environment.domains.errorMessage
      }
    }
  }
}

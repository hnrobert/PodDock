import SwiftUI
import DNSPodKit

/// 记录表单:类型/线路下拉(recordOptions 缓存拉取)、默认值、客户端预校验。
struct RecordFormView: View {
  /// 表单模式(.create 新建 / .edit 编辑回填)
  enum FormMode {
    case create(domain: DNSDomain)
    case edit(domain: DNSDomain, record: DNSRecord)
  }

  @Environment(AppEnvironment.self) private var environment
  @Environment(\.dismiss) private var dismiss
  let onSaved: () -> Void

  private let domain: DNSDomain
  private let original: DNSRecord?
  private var isCreate: Bool { original == nil }

  @State private var subDomain = ""
  @State private var recordType = "A"
  @State private var recordLine = "默认"
  @State private var value = ""
  @State private var mxText = "10"
  @State private var ttlText = "600"
  @State private var remark = ""

  @State private var options: RecordOptions?
  @State private var isLoadingOptions = false
  @State private var isSaving = false
  @State private var errorMessage: String?

  init(mode: FormMode, onSaved: @escaping () -> Void = {}) {
    switch mode {
    case .create(let domain):
      self.domain = domain
      self.original = nil
    case .edit(let domain, let record):
      self.domain = domain
      self.original = record
    }
    self.onSaved = onSaved
  }

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section("记录") {
          LabeledContent("主机记录") {
            TextField("主机记录", text: $subDomain, prompt: Text("@ 或 www"))
          }
          LabeledContent("记录类型") {
            if let options, !options.types.isEmpty {
              Picker("", selection: $recordType) {
                ForEach(options.types, id: \.self) { Text($0).tag($0) }
              }
              .labelsHidden()
            } else {
              TextField("A", text: $recordType)
            }
          }
          LabeledContent("线路") {
            if let options, !options.lines.isEmpty {
              Picker("", selection: $recordLine) {
                ForEach(options.lines, id: \.self) { Text($0).tag($0) }
              }
              .labelsHidden()
            } else {
              TextField("默认", text: $recordLine)
            }
          }
          LabeledContent("记录值") {
            TextField("记录值", text: $value, prompt: Text(valueHint))
          }
          if recordType == "MX" {
            LabeledContent("MX 优先级") {
              TextField("MX 优先级", text: $mxText, prompt: Text("10"))
            }
          }
          LabeledContent("TTL(秒)") {
            TextField("TTL", text: $ttlText, prompt: Text("600"))
          }
        }

        Section("备注") {
          TextField("备注", text: $remark, prompt: Text("可选"))
        }

        if isLoadingOptions {
          Section {
            HStack {
              ProgressView().controlSize(.small)
              Text("正在获取可用类型与线路…")
            }
            .foregroundStyle(.secondary)
          }
        }
        if let errorMessage {
          Section { Text(errorMessage).foregroundStyle(.red) }
        }
      }
      .formStyle(.grouped)

      HStack {
        Text(isCreate ? "添加记录" : "修改记录 \(original?.name ?? "")")
          .font(.headline)
        Spacer()
        if isSaving {
          ProgressView().controlSize(.small)
        }
        Button("取消") { dismiss() }
        Button("保存", action: save)
          .buttonStyle(.borderedProminent)
          .disabled(!isValid || isSaving)
      }
      .padding(14)
    }
    .frame(minWidth: 460, minHeight: 500)
    .task {
      populate()
      await loadOptions()
    }
  }

  private var valueHint: String {
    switch recordType {
    case "A": "IPv4 地址,如 203.0.113.10"
    case "AAAA": "IPv6 地址"
    case "CNAME": "目标主机名"
    case "MX": "邮件服务器主机名"
    case "TXT": "文本内容"
    default: "记录值"
    }
  }

  private var isValid: Bool {
    let trimmedValue = value.trimmingCharacters(in: .whitespaces)
    guard !trimmedValue.isEmpty else { return false }
    if recordType == "A", !Self.isIPv4(trimmedValue) { return false }
    if Int(ttlText) == nil { return false }
    if recordType == "MX", Int(mxText) == nil { return false }
    return true
  }

  private func populate() {
    guard let original else { return }
    subDomain = original.name
    recordType = original.type
    recordLine = original.line
    value = original.value
    mxText = String(original.mx)
    ttlText = String(original.ttl)
    remark = original.remark
  }

  private func loadOptions() async {
    guard let client = environment.client else { return }
    isLoadingOptions = true
    defer { isLoadingOptions = false }
    do {
      options = try await client.recordOptions(for: domain)
      // 当前值不在选项里时(如旧线路),回落到第一项避免 Picker 丢值
      if let options, !options.types.contains(recordType) {
        recordType = options.types.first ?? recordType
      }
      if let options, !options.lines.contains(recordLine) {
        recordLine = options.lines.first ?? recordLine
      }
    } catch {
      errorMessage = "类型/线路获取失败:\(error.localizedDescription)(可直接手填)"
    }
  }

  private func save() {
    Task {
      isSaving = true
      defer { isSaving = false }
      guard let client = environment.client else { return }

      let draft = RecordDraft(
        subDomain: subDomain,
        recordType: recordType,
        recordLine: recordLine,
        value: value.trimmingCharacters(in: .whitespaces),
        mx: Int(mxText),
        ttl: Int(ttlText),
        remark: remark)

      do {
        if let original {
          try await client.updateRecord(id: original.id, in: domain, from: original, to: draft)
        } else {
          _ = try await client.createRecord(draft, in: domain)
        }
        onSaved()
        dismiss()
      } catch let error as DNSPodError {
        if case .remarkFailed = error {
          // 部分失败:主操作已成功,照常关闭并刷新
          onSaved()
          dismiss()
          return
        }
        errorMessage = error.localizedDescription
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  /// 简单 IPv4 预校验(参考实现完全没有校验,全靠服务端报错)
  static func isIPv4(_ text: String) -> Bool {
    let parts = text.split(separator: ".")
    guard parts.count == 4 else { return false }
    return parts.allSatisfy { part in
      guard let number = Int(part), (0...255).contains(number) else { return false }
      return part.count == String(number).count  // 拒绝前导零
    }
  }
}

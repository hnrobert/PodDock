import SwiftUI
import DNSPodKit

/// Record form: type/line pickers (cached recordOptions), defaults, client-side pre-validation.
struct RecordFormView: View {
  /// Form mode (.create new / .edit pre-filled)
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
        Section("Record") {
          LabeledContent("Host") {
            TextField("", text: $subDomain, prompt: Text("@ or www"))
          }
          LabeledContent("Record Type") {
            if let options, !options.types.isEmpty {
              Picker("", selection: $recordType) {
                ForEach(options.types, id: \.self) { Text($0).tag($0) }
              }
              .labelsHidden()
            } else {
              TextField("", text: $recordType)
            }
          }
          LabeledContent("Line") {
            if let options, !options.lines.isEmpty {
              Picker("", selection: $recordLine) {
                ForEach(options.lines, id: \.self) { Text($0).tag($0) }
              }
              .labelsHidden()
            } else {
              TextField("", text: $recordLine)
            }
          }
          LabeledContent("Value") {
            TextField("", text: $value, prompt: Text(valueHint))
          }
          if recordType == "MX" {
            LabeledContent("MX Priority") {
              TextField("", text: $mxText, prompt: Text("10"))
            }
          }
          LabeledContent("TTL (seconds)") {
            TextField("", text: $ttlText, prompt: Text("600"))
          }
        }

        Section("Remark") {
          TextField("", text: $remark, prompt: Text("Optional"))
        }

        if isLoadingOptions {
          Section {
            HStack {
              ProgressView().controlSize(.small)
              Text("Loading available types and lines…")
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
        Text(isCreate ? "Add Record" : "Edit Record \(original?.name ?? "")")
          .font(.headline)
        Spacer()
        if isSaving {
          ProgressView().controlSize(.small)
        }
        Button("Cancel") { dismiss() }
        Button("Save", action: save)
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
    case "A": "IPv4 address, e.g. 203.0.113.10"
    case "AAAA": "IPv6 address"
    case "CNAME": "Target hostname"
    case "MX": "Mail server hostname"
    case "TXT": "Text content"
    default: "Value"
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
      // When the current value is absent from options (e.g. an old line), fall back to the first so the Picker doesn't drop it
      if let options, !options.types.contains(recordType) {
        recordType = options.types.first ?? recordType
      }
      if let options, !options.lines.contains(recordLine) {
        recordLine = options.lines.first ?? recordLine
      }
    } catch {
      errorMessage = String(
        localized: "Failed to load types/lines: \(describeError(error)) (you can type manually)")
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
          // Partial failure: the main op succeeded — close and refresh anyway
          onSaved()
          dismiss()
          return
        }
        errorMessage = describeError(error)
      } catch {
        errorMessage = describeError(error)
      }
    }
  }

  /// Simple IPv4 pre-check (the reference validated nothing and leaned on server errors)
  static func isIPv4(_ text: String) -> Bool {
    let parts = text.split(separator: ".")
    guard parts.count == 4 else { return false }
    return parts.allSatisfy { part in
      guard let number = Int(part), (0...255).contains(number) else { return false }
      return part.count == String(number).count  // reject leading zeros
    }
  }
}

import Foundation
import DNSPodKit

// poddock-capture —— 真实 API 响应抓取工具(M1 验收:fixture 录制 + 错误码表核对)。
//
// 在 DNSPodKit/ 目录下运行:
//
//   DNSPOD_TOKEN="ID,Token" swift run poddock-capture --domain example.com
//   # 追加 --record-id 123:额外抓 Record.Info
//   # 追加 --full:在该域名上走临时记录完整生命周期(create/remark/modify/status/remove)
//
// 产物写入 Tests/DNSPodKitTests/Fixtures/*.json。
// ⚠️ 文件内容含你账户的真实域名/记录,提交前自行脱敏!

let arguments = CommandLine.arguments.dropFirst()
var domain: String?
var recordID: String?
var full = false
var iterator = arguments.makeIterator()
while let flag = iterator.next() {
  switch flag {
  case "--domain": domain = iterator.next()
  case "--record-id": recordID = iterator.next()
  case "--full": full = true
  default:
    print("未知参数:\(flag)")
    exit(2)
  }
}

let environment = ProcessInfo.processInfo.environment
guard let pasted = environment["DNSPOD_TOKEN"], let token = Account.parse(pasted: pasted) else {
  FileHandle.standardError.write(
    Data(
      """
      缺少凭据。用法:
        DNSPOD_TOKEN="ID,Token" swift run poddock-capture --domain <你的域名> [--record-id <id>] [--full]
      Token 在 DNSPod 控制台 → 「API 密钥」创建。
      """.utf8))
  exit(1)
}

let client = LegacyClient(tokenID: token.id, tokenKey: token.token)
let outputDirectory = URL(fileURLWithPath: "Tests/DNSPodKitTests/Fixtures")

func capture(_ name: String, _ action: String, _ params: [String: String]) async {
  do {
    let data = try await client.rawResponse(action, params)
    let pretty =
      (try? JSONSerialization.jsonObject(with: data))
      .flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.prettyPrinted, .sortedKeys]) }
      ?? data
    let url = outputDirectory.appendingPathComponent("\(name).json")
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    try pretty.write(to: url)
    print("✓ \(name)(\(action))→ \(url.path)")
  } catch {
    print("✗ \(name)(\(action)):\(error.localizedDescription)")
  }
}

func printReminder() {
  print("提醒:Fixtures 含真实账户数据,提交前请脱敏;错误码表请对照抓到的错误响应补进 DNSPodError.isAuthenticationFailure。")
}

print("poddock-capture 开始抓取…(只读端点)")
await capture("domain_list", "Domain.List", [:])
await capture("record_types", "Record.Type", ["domain_grade": "DP_Free"])
await capture("record_lines", "Record.Line", ["domain_id": "0", "domain_grade": "DP_Free"])

if let domain, !domain.isEmpty {
  do {
    let domains = try await client.listDomains()
    guard let found = domains.first(where: { $0.name == domain }) else {
      print("✗ 账户下未找到域名 \(domain)(可用:\(domains.map(\.name).joined(separator: ", ")))")
      printReminder()
      exit(1)
    }
    let domainID = found.id.rawValue
    await capture("record_list", "Record.List", ["domain_id": domainID])
    await capture("record_lines_domain", "Record.Line", ["domain_id": domainID, "domain_grade": found.grade])

    if let recordID {
      await capture("record_info", "Record.Info", ["domain_id": domainID, "record_id": recordID])
    }

    if full {
      print("--full:临时记录生命周期(_poddocap 子域,结束后自动删除)")
      let draft = RecordDraft(
        subDomain: "_poddocap", recordType: "A", recordLine: "默认",
        value: "203.0.113.1", remark: "poddock-capture 临时记录")
      do {
        let record = try await client.createRecord(draft, in: found)
        print("✓ 已创建临时记录 \(record)")
        try await Task.sleep(for: .seconds(2))  // 新记录有短暂索引延迟

        let created = try await client.fetchRecord(id: record, domainID: found.id)
        await capture("record_info", "Record.Info", ["domain_id": domainID, "record_id": record.rawValue])
        try await client.setRecordStatus(id: record, domainID: found.id, to: .disable)
        print("✓ 已暂停")
        try await client.setRecordStatus(id: record, domainID: found.id, to: .enable)
        print("✓ 已恢复启用")
        try await client.updateRecord(
          id: record, in: found, from: created,
          to: RecordDraft(
            subDomain: "_poddocap", recordType: "A", recordLine: "默认",
            value: "203.0.113.2", remark: "poddock-capture 修改后"))
        print("✓ 已修改")
        try await client.removeRecord(id: record, domainID: found.id)
        print("✓ 已删除临时记录,清理完成")
      } catch {
        print("✗ 生命周期中断:\(error.localizedDescription)(残留的 _poddocap 记录请手动删除)")
      }
    }
  } catch {
    print("✗ \(error.localizedDescription)")
  }
} else {
  print("未指定 --domain,跳过需要域名上下文的端点。")
}
printReminder()

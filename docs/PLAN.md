# PodDock 实施计划

## Context

PodDock 是 DNSPod 的原生 SwiftUI 客户端,2026-08-30 立项,从 dnspod-api-python-web(Li Kexian 的 Flask 示例,仅作 API 行为参考)移植。24 个收敛问题 + 1 个 API 纠正重选已定案;本计划固化为可执行方案。

首版目标:**macOS 全功能可自用**(域名/记录管理 + 列表增强 + DoH 检测),iOS 复用代码后移植,全程按可上架标准预留。

## 已确认决策

| 维度 | 决策 |
| --- | --- |
| 平台 | macOS 15 / iOS 18 起;单 App target `supportedDestinations = [.macOS, .iOS]`,macOS 先行 |
| 分发 | 自用优先,按可上架标准预留(bundle id、权限、隐私清单) |
| 界面语言 | 中英双语,首版即用 String Catalog(**英文为源语言与代码字面量(键),zh-Hans 为翻译**;动态消息走 `String(localized:)`;DNSPod 线路名等线格式数据值不本地化) |
| API | 双实现适配层:`DNSPodClient` 协议(意图级)+ LegacyClient(传统 API);TencentCloudClient(TC3)占位,M5 升级最小实现 |
| 账户 | 多账户可切换;Face ID / Touch ID 应用锁可选开关 |
| 登录辅助 | 粘贴 `ID,Token` 自动拆分 + 控制台引导链接 |
| 功能范围 | 域名/记录全 CRUD + 启停 + 备注;搜索/筛选/排序/批量/备注快编;DoH 生效检测;DDNS 远期 |
| LLM 助手 | App 内自然语言操作:**本地执行**(App 直连 LLM,工具定义以 MCP 标准 schema 为统一契约,经 DNSPodKit 执行);危险操作仍走确认框 |
| LLM 提供商 | 双协议可选:Anthropic 官方 `/v1/messages`(Swift 无官方 SDK,原生 HTTP 实现,默认 `claude-opus-5`)+ OpenAI 兼容端点(自定义 base URL + key) |
| MCP 服务器 | **PodDockMCP**:Swift(官方 [modelcontextprotocol/swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) + Hummingbird v2),**仅提供 Streamable HTTP 服务**(不做 stdio);**启动零凭据**——客户端在会话内调用 `dnspod_login` 工具认证,凭据绑定 `Mcp-Session-Id` 会话(每客户端一套 transport+Server 连接池);同一服务库双宿主:① Linux 独立 executable(Docker 部署)② **内嵌于 macOS App**;App 内不出现任何外部 MCP 端点配置 |
| 工程 | Xcode 工程 + 本地 SPM 包;`@Observable` MV;URLSession 自封装零依赖 |
| 测试 | swift-testing 单测(DNSPodKit)+ XCUITest 关键流程(UI 测试只能 XCTest) |
| UI | 系统风 + 品牌绿;macOS 首屏即域名列表;危险操作确认框;定制豌豆荚图标 |
| CI | 参考 MultiScreenCapturer 模式,但 action 版本升级、修正脆弱判定、补 notarization |
| 其他 | README 仅中文;版本 0.1.0 起;远期:菜单栏、小组件+快捷指令、watchOS、CLI |

传统 API 公共参数(官方文档已核实):`login_token`=`ID,Token`、`format=json`、`lang=cn`、`error_on_empty=no`;仅主账号;官方已标 legacy(适配层即对冲)。

## 仓库结构

```text
PodDock/
├── PodDock.xcodeproj              # 单 App target,双平台;共享 scheme 提交进仓库
├── DNSPodKit/                     # 本地 SPM 包(swift-tools-version 6.0,单包多 product)
│   ├── Package.swift              # products: DNSPodKit 库 + PodDockMCP 服务库 + poddock-mcp 可执行
│   ├── Sources/DNSPodKit/         # 零第三方依赖,Apple + Linux 双干净
│   │   ├── DNSPodClient.swift     # 意图级协议 + Capability + 错误契约
│   │   ├── Clients/
│   │   │   ├── LegacyClient.swift         # dnsapi.cn + login_token,13 操作
│   │   │   └── TencentCloudClient.swift   # 占位空壳(M5 最小实现)
│   │   ├── Networking/            # HTTPTransport 协议 + URLSessionTransport + MockTransport
│   │   ├── Models/                # Domain/Record/RecordDraft + DomainID/RecordID 强类型
│   │   ├── FlexDecodable.swift    # 数字/字符串容错解码
│   │   ├── DNSPodError.swift      # .api(code:message:) / .remarkFailed / isAuthenticationFailure
│   │   ├── RecordOptionsProvider.swift    # type 按 grade、line 按 domain_id 缓存(Kit 内!)
│   │   ├── AccountStore.swift     # 协议 + InMemoryAccountStore(Keychain 实现放 App,iOS/macOS 专用)
│   │   ├── MCPToolCatalog.swift   # MCP 标准工具 schema,App 与 PodDockMCP 的单一契约源
│   │   └── DoH/DoHResolver.swift  # 多 provider + 系统解析回退
│   ├── Sources/PodDockMCP/        # MCP 服务库(可嵌入,swift-sdk + Hummingbird 仅挂此依赖)
│   │   ├── MCPServerService.swift # Streamable HTTP 服务,注入任意 DNSPodClient 即起服务
│   │   ├── ToolHandlers.swift     # MCPToolCatalog → DNSPodClient 装配
│   │   └── Config.swift           # 端口/Bearer/凭据(环境变量或由宿主注入)
│   ├── Sources/PodDockMCPCli/     # Linux 独立部署 executable(薄壳:env → 服务库)
│   └── Tests/                     # swift-testing + Fixtures/*.json + ConformanceTests
│                                  # + MCP 集成测试(swift-sdk 客户端经 HTTP 打测试内服务)
├── PodDock/                       # App 源码
│   ├── App/                       # PodDockApp / AppEnvironment / RootScene(#if os 分支)
│   ├── Views/                     # AddAccountView/AccountView/DomainListView/RecordListView/RecordFormView/DoHPanelView/AssistantView/AppLockView/SettingsView/Components
│   ├── Models/                    # ~7 个 app 级 @Observable model(+AssistantModel)
│   ├── Services/                  # MockDNSPodClient(#if DEBUG,有状态)/ PreferencesStore / KeychainAccountStore
│   │   ├── LLM/                   # AnthropicClient(/v1/messages)+ OpenAICompatClient + ToolLoop
│   │   └── MCPHostService.swift   # macOS 内嵌 MCP 宿主(开关/端口/Bearer,注入当前账户 client)
│   ├── Resources/                 # Localizable.xcstrings / Assets / PrivacyInfo.xcprivacy
│   └── UITests/                   # XCUITest(mock 模式)
├── Dockerfile                     # poddock-mcp 镜像(swift:6 基础镜像)
├── .github/workflows/{ci,release}.yml
├── docs/PLAN.md                   # 本计划落盘仓库
└── README.md                      # 中文
```

## 核心设计决策

### 适配层:意图级协议,不是端点镜像

两个 API 的差异在**组合方式与参数语义**,不在端点,所以协议按业务语义定义:

```swift
protocol DNSPodClient: Sendable {
  var capabilities: Set<Capability> { get }  // .inlineRemark / .batchStatus / .pagination
  func validateCredentials() async throws    // Legacy 实现 = listDomains()(error_on_empty=no,空账户也 code 1)
  func listDomains() async throws -> [DNSDomain]
  func createDomain(name: String) async throws
  func setDomainStatus(id: DomainID, to: DomainStatus) async throws
  func removeDomain(id: DomainID) async throws
  func listRecords(domainID: DomainID) async throws -> RecordListPage  // 首日就按分页建模
  func recordOptions(for domain: DNSDomain) async throws -> RecordOptions
  func createRecord(_ draft: RecordDraft, in domain: DNSDomain) async throws -> RecordID
  func updateRecord(id: RecordID, in domain: DNSDomain, from: DNSRecord, to: RecordDraft) async throws
  func setRecordStatus(id: RecordID, domainID: DomainID, to: RecordStatus) async throws
  func removeRecord(id: RecordID, domainID: DomainID) async throws
  func setRecordRemark(id: RecordID, domainID: DomainID, remark: String) async throws
}
```

- `updateRecord(from:to:)`:LegacyClient 内部决定"备注变化才补调 `Record.Remark`",TC3 直接内联——行为差异留在 Kit 层,App 不感知
- `sub_domain=@` / `MX=10` / `TTL=600` 默认值在 `RecordDraft` 构造层
- **部分失败契约**:Modify+Remark 两次调用不原子,定义 `DNSPodError.remarkFailed`,UI 非阻塞提示
- **ConformanceTests**(swift-testing 参数化):同一组行为断言跑 Legacy 与未来 TC3,协议漏抽象立即暴露

### Networking 层(测试支点)

- `HTTPTransport` 协议 + `URLSessionTransport`(生产)+ `MockTransport`(单测/UI 测试/Preview 共用)
- 公共参数统一注入、`status.code == 1` 判定、User-Agent `PodDock/<version> (+repo)`、30s 超时
- 凭据会话用 `URLSessionConfiguration.ephemeral` + `reloadIgnoringLocalCacheData`,token 与记录数据不落 URLCache;请求体永不进日志

### 多账户 Keychain

- 每账户一条 generic password:service=常量(随 bundle id 定),account=UUID(不用 Token ID 当 key),value=JSON `{id,label,apiFlavor,loginTokenID,loginToken,createdAt}`
- `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` + **macOS 必须设 `kSecUseDataProtectionKeychain=true`**(否则与 iOS 行为分叉,最常踩的坑)
- 当前账户 UUID、账户标签存 UserDefaults;凭据只进 Keychain;全部经 `AccountStore` 协议
- 账户标签本地手填(传统 API 无账户资料接口),默认 `账户 <ID 后 4 位>`

### LLM 助手(App 本地执行)

- `AssistantView`(命令栏/对话式):自然语言 → LLM(流式)→ MCP 标准工具调用 → **本地经 DNSPodClient 执行** → 结果回传循环至完成;操作结果在 UI 中 diff 展示
- **单一契约源**:`MCPToolCatalog`(DNSPodKit 内)定义全部工具的 JSON Schema——App 的 LLM tool definitions 与 PodDockMCP 的 MCP tools 由同一份目录生成,永不漂移
- **安全边界**:LLM 只能"提议"操作;删除/修改等破坏性工具调用必须经用户确认框后才执行;DNS 数据(记录值、备注)作为 data 传给 LLM,防提示注入(不解释为指令)
- 双提供商:`AnthropicClient`(`/v1/messages` 原生 HTTP,流式 SSE + tool use + adaptive thinking,默认 `claude-opus-5`)与 `OpenAICompatClient`(可配 base URL 的 `/chat/completions`);统一 `LLMProviding` 协议 + `ToolLoop` 执行器;key 存 Keychain
- UI 测试:LLM 层同样可注入 mock(`MockLLMProvider` 按脚本回放工具调用)

### PodDockMCP(同一服务库,双宿主)

- 官方 [swift-sdk](https://github.com/modelcontextprotocol/swift-sdk)(client+server 双实现)+ Hummingbird v2,只暴露 **Streamable HTTP** 端点(不做 stdio);服务库与 API 调用解耦:注入任意 `DNSPodClient` 即工作
- **认证模型(启动零凭据)**:服务器不带任何内置 token;MCP 客户端在会话内调用 `dnspod_login` 工具(整串 "ID,Token" 或分字段)→ 服务端用 LegacyClient 验证(HTTP 401 归一为认证失败)→ 凭据绑定该 `Mcp-Session-Id` → 后续工具调用全部用会话 client;`dnspod_logout` 清除。`StatefulHTTPServerTransport` 是单会话 transport,多客户端由 `MCPConnectionPool` 每会话一套 transport+Server,空闲 1 小时回收
- **宿主一:Linux 独立 executable**(`poddock-mcp`,Docker 部署):`MCP_AUTH_TOKEN` 可选 Bearer 保护端点(与账户认证相互独立)
- **宿主二:内嵌 macOS App**:设置内开关"本地 MCP 服务",监听 127.0.0.1,自动生成 Bearer token 并给出 `claude mcp add --transport http --header ...` 一键复制接入串;客户端同样走 dnspod_login 认证(或注入共享当前账户的 client 工厂);iOS 不内嵌
- 工具面 = `dnspod_login` / `dnspod_logout` + `MCPToolCatalog`:list_domains / create_domain / set_domain_status / remove_domain / list_records / record_options / create_record / update_record / set_record_status / remove_record / set_record_remark / check_propagation(DoH);带 read-only / destructive 注解
- App 的 LLM 助手与 MCP **互不依赖**:助手本地执行(不经 MCP 协议),App 设置里没有外部 MCP 端点项;代价:App 经 PodDockMCP 库引入 swift-sdk + Hummingbird(纯 Swift,依赖与体积增量可接受)
- 集成测试:swift-sdk 客户端经 HTTP 对测试内服务跑 initialize + tools/call 全链路(离线),同一 suite 覆盖两种宿主装配

### DNSPodKit 的 Linux 纯净性(硬约束)

- Kit 只依赖 Foundation;`KeychainAccountStore` 移入 App target(Security 框架 Apple 专用),Kit 内只留 `AccountStore` 协议与 `InMemoryAccountStore`
- 需要 `#if canImport(FoundationNetworking)` 处的 URL 加载 gating(Linux 的 URLSession 在 FoundationNetworking)
- CI 加 ubuntu job:`swift test`(Kit)+ `swift build --product poddock-mcp`,锁住跨平台纯净性

## API 映射(传统 API → App 功能,依据 app.py 实证)

| API | 线格式要点 | App 功能 |
| --- | --- | --- |
| `Domain.List` | `{}`;**兼作凭据验证** | 首屏域名列表 + 添加账户时校验 |
| `Domain.Create` | `{domain}` | 添加域名 |
| `Domain.Status` | `{domain_id,status}`;参考实现发 `enable`/`disable`,官方文档写 `enable\|pause`;首版照抄参考实现,真实域名验证一次 | 域名启停 |
| `Domain.Remove` | `{domain_id}` | 删除域名(确认框) |
| `Record.List` | `{domain_id}`;响应含 `domain.grade` 是表单权威来源 | 记录列表;分页行为 M1 实测 |
| `Record.Type` | `{domain_grade`(参数名不是 grade) | 表单记录类型下拉,**按 grade 缓存** |
| `Record.Line` | `{domain_id,domain_grade}` | 线路下拉,按 domain_id 缓存 |
| `Record.Info` | `{domain_id,record_id}` | 编辑表单回填 |
| `Record.Create` | 7 字段;返回 `record.id` 供 Remark 用 | 新建记录 |
| `Record.Modify` | Create + `record_id` | 编辑记录 |
| `Record.Remark` | 创建后备注非空补调;修改时 `remark != oremark` 才调;快编直调 | 备注(Kit 内组合) |
| `Record.Remove` / `Record.Status` | enable/disable | 删除(确认框)/启停 |
| —(DoH,不走 dnsapi.cn) | 默认 doh.pub + 阿里 `dns.alidns.com/resolve`,可自定义;3–5s 超时回退系统解析并标注来源 | 生效检测 |

批量操作无对应端点:顺序循环 + 节流,失败逐条汇总。

## 里程碑

| 期 | 内容 | 版本 | 验收标准 |
| --- | --- | --- | --- |
| M0 骨架 | SPM 包 + Xcode 双平台工程、空协议/空实现、String Catalog 骨架、PrivacyInfo 占位、entitlements(`network.client` 第一天就配)、ci.yml、docs/PLAN.md、`.editorconfig`/`.markdownlint.json` | 0.1.0 | macOS + iOS Simulator 双 build 绿;`swift test` 跑通;scheme 已提交 |
| M1 Kit 全量 + 只读 | Networking/FlexDecodable/13 操作/错误分类;fixture 用真 token 手工录(含错误响应,补码表);App:粘贴添加账户、域名/记录列表、搜索/筛选/排序 | 0.2.0 | 13 操作全有 MockTransport+fixture 单测;真 token 空账户与多记录账户浏览正常;未知 grade 不崩;测试全离线 |
| M2 macOS 全功能 | 增删改/启停/备注快编/批量(节流)/表单+选项缓存/确认框/DoH(带回退)/应用锁/统一错误呈现(含部分成功) | 0.4.0 | 完全脱离网页控制台自用;type/line 每键只拉一次、Remark 恰好一次(MockTransport 断言);批量 20 条不撞限流;重启状态保持 |
| M3 LLM 助手 + MCP 服务 | MCPToolCatalog、AssistantView + ToolLoop + 双 LLM 协议、PodDockMCP 服务库(Linux executable + macOS 内嵌宿主)、Dockerfile、CI ubuntu job | 0.5.0 | 自然语言完成"查域名→改记录→验证生效"全流程且破坏性操作有确认;Claude Code 分别接入服务器端点与 App 内嵌端点(同账户)均成功;Linux CI 绿 |
| M4 iOS 移植 | 紧凑态导航、iOS 设置页(macOS 用 Settings scene)、Face ID 锁、iOS UI 测试、CI 加 iOS lane;Keychain iOS 真机验证 | 0.7.0 | 双平台 CI 绿;iPhone 模拟器 UI 测试全流程;macOS 不回归 |
| M5 上架就绪 | 正式 bundle id/证书、Hardened Runtime 终审、隐私清单与出口合规、全尺寸图标(含 iOS 18 dark/tinted)、VoiceOver/键盘、商店元数据、TencentCloudClient 最小实现(验证抽象成立)、release.yml 补 **notarization+staple** | 1.0.0 | 签名公证产物可分发;TestFlight 可用;VoiceOver 全流程可走 |
| 远期 | 菜单栏、小组件+快捷指令、watchOS、CLI(环境变量实现 AccountStore)、TC3 全量、DDNS | — | — |

## 测试策略

- **单测**(swift-testing,`swift test` 可独立跑):FlexDecodable 数字字符串、请求构造(公共参数/login_token 格式/`record_line_id` 的 `=` 转义)、fixture 解码、错误映射、ConformanceTests
- **UI 测试**(XCTest):App 读 launch argument `--uitest-mock` 切 `MockDNSPodClient`(有内存状态的确定性状态机,支持失败注入)+ `InMemoryAccountStore`;场景参数如 `--uitest-scenario auth_failure`
- 定位一律用 accessibility identifier(`domain-row-<id>`),不用本地化文本;macOS 右键菜单 XCUITest 难驱动,删除等操作同时提供工具栏/菜单入口
- 5–8 条关键流程控制 CI 时长;`-AppleLanguages (en)` 冒烟一条;`-retry-tests-on-failure` 只用于 UI lane

## CI / 交付

参考 MultiScreenCapturer 模式:push/PR → `macos-latest` + `setup-xcode` latest-stable,免签名 build + test(双 destination),xcresult 上传并以 `xcresulttool get test-results summary` 判定(**不照抄** `|| true`+grep 的脆弱补丁);另加 **ubuntu job**:`swift test` + `swift build --product poddock-mcp`(锁 Linux 纯净性);tag `v*` → 签名 archive + zip + gh-release + notarization。**发布产物仅 arm64**(Apple Silicon,archive 按 `-arch arm64` 出包,不做 universal);poddock-mcp 视需要随 release 出 Docker 镜像或静态二进制(M3 时与 hnrobert-github-actions 访谈定)。action 升级:`checkout@v4+`、`upload-artifact@v4`、`setup-xcode@v1`、`action-gh-release@v2`。**写 workflow 前按 hnrobert-github-actions 规范做模板访谈**。

## 风险与对策

| 风险 | 对策 |
| --- | --- |
| 传统 API legacy、Token 全权 | 适配层 + TC3 占位;Keychain ThisDeviceOnly + 应用锁;README 标注 |
| JSON 数字当字符串(`enabled/mx/ttl/records/id`) | FlexDecodable + fixture 用例;ID 用 String/UInt64 强类型包装 |
| `updated_on` 非 ISO8601(`2024-01-01 12:00:00`) | 自定义 DateFormatter |
| Record.List 分页行为未知 | M1 用 >100 记录域名实测;返回类型首日即 `RecordListPage` |
| 批量无限流端点 | 顺序 + 小间隔节流,失败逐条汇总 |
| DoH 大陆可达性(dns.google 基本不可用) | 默认 doh.pub / alidns,可自定义;超时回退系统解析并标注来源 |
| `lang=cn` 错误消息无法本地化 | 已知码映射本地化文案,未知码原样透传;错误码表靠 M1 真实 fixture |
| Swift 6 语言模式严格并发 | 接受严格模式按 actor/@Sendable 写;排期预留半天 |
| macOS Keychain 行为分叉 | `kSecUseDataProtectionKeychain=true`;iOS 真机验证 |
| 手写 xcodeproj 易错 | Xcode 16 fileSystemSynchronized 组格式(极简 pbxproj);失败退回用户 Xcode 新建空工程 |
| swift-sdk 尚未 1.0,API 会动 | Package.swift 钉精确版本;MCPToolCatalog 隔离工具定义与 SDK 类型,升级只动 Server 层 |
| LLM 提示注入(记录值/备注进入上下文) | DNS 数据一律作为 data 传给模型;破坏性操作必须用户确认后才执行;工具白名单只有 DNS 域 |
| Anthropic 无官方 Swift SDK | 原生 HTTP + SSE 手写实现(流式/tool use),用 MockLLMProvider 回放脚本测试;请求层保持薄,便于跟进 API 变化 |
| Linux URLSession 差异 | `#if canImport(FoundationNetworking)` gating + ubuntu CI job 兜底 |

## 容易遗漏的工程项(已纳入)

- entitlements:`app-sandbox` + `network.client`(缺它 API 全挂且报错不直观);iOS `NSFaceIDUsageDescription`
- `PrivacyInfo.xcprivacy`:`NSPrivacyAccessedAPICategoryUserDefaults`(C56D.1);`ITSAppUsesNonExemptEncryption=false`;`LSApplicationCategoryType=Developer Tools`
- `xcshareddata/xcschemes` 必须提交;`.gitignore` 勿误伤
- 图标:macOS 1024 去 alpha;iOS 全套 + dark/tinted;两套 appiconset 按平台条件化
- 空态即正常态(error_on_empty=no);`spam/lock` 状态域名只展示不可切换;客户端预校验(IPv4 格式等)
- 刷新:macOS 聚焦自动 + 工具栏;iOS 下拉

## 关键文件

- `DNSPodKit/Sources/DNSPodKit/DNSPodClient.swift` — 意图级协议 + Capability + 错误契约,全计划支点
- `DNSPodKit/Sources/DNSPodKit/Clients/LegacyClient.swift` — 13 操作映射、remark 补调、默认值补齐
- `DNSPodKit/Sources/DNSPodKit/Networking/HTTPTransport.swift` — Mock 复用层,决定测试能否离线
- `DNSPodKit/Sources/DNSPodKit/MCPToolCatalog.swift` — MCP 标准工具 schema,App LLM 与 PodDockMCP 的单一契约源
- `DNSPodKit/Sources/PodDockMCP/MCPServerService.swift` — 可嵌入的 Streamable HTTP 服务装配(双宿主共用)
- `PodDock/Services/LLM/ToolLoop.swift` — 双协议统一的工具调用循环 + 确认门
- `PodDock/Services/MockDNSPodClient.swift` — Preview + XCUITest 共用状态机
- `.github/workflows/ci.yml` — 双平台 destination + ubuntu job、修正判定

## Verification

- 构建:`xcodebuild -scheme PodDock -destination 'platform=macOS' build`(CI 另跑 iOS Simulator)
- Kit 快速 lane:`swift test`(DNSPodKit,host 可跑);Linux:`swift build --product poddock-mcp`(ubuntu CI)
- MCP:Claude Code 以 HTTP transport 接入两宿主——服务器端点(Docker/本机起 poddock-mcp)与 App 内嵌端点(开开关后一键复制接入串),tools/call 全链路且操作反映到同一账户
- LLM 助手(M3 起):真 key 下"帮我把 www 的 A 记录改成 x.x.x.x 并验证生效"全流程,破坏性操作弹确认;`MockLLMProvider` 回放脚本跑 UI 测试
- 手动验收(M2 起):真 token 添加账户 → 域名列表 → 加记录(备注)→ DoH 验证生效 → 启停 → 批量删 → 切账户 → 应用锁 → 杀进程重启状态保持
- CI 绿灯;`-AppleLanguages (en)` 冒烟双语文案

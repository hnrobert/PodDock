# PodDock

DNSPod 原生客户端(Swift 版):macOS / iOS App + 可独立部署的 MCP 服务,一套代码三种形态。

## 功能

- 多账户 Token 管理(Keychain 存储,可选 Face ID / Touch ID 应用锁)
- 域名与解析记录的增删改、启停、备注,搜索 / 类型筛选 / 排序 / 批量操作
- DoH 解析生效检测(默认腾讯 doh.pub / 阿里 alidns,可自定义)
- LLM 助手:自然语言直接操作解析("把 www 的 A 记录改成 1.2.3.4"),本地执行、破坏性操作需确认
- MCP 服务([Model Context Protocol](https://modelcontextprotocol.io/)):仅 Streamable HTTP,**启动零凭据**——客户端在会话内调用 `dnspod_login` 工具提供 DNSPod Token 认证,凭据绑定该会话;同一服务库双宿主(Linux 独立部署 / 内嵌 macOS App)

## 架构

```text
DNSPodKit(SPM 包)
├── DNSPodKit 库       # 意图级 DNSPodClient 协议 + LegacyClient(传统 API)+ DoH,零第三方依赖
├── PodDockMCP 服务库  # MCP Streamable HTTP 服务,注入任意 DNSPodClient 即工作
└── poddock-mcp        # Linux 独立部署 executable(Docker)

PodDock(App)          # SwiftUI 多平台(macOS 先行),@Observable MV
```

API 采用双实现适配层:首版实现传统 API(`dnsapi.cn` + `login_token`),预留腾讯云 API 3.0(TC3 签名)实现位。

## 构建

```bash
# DNSPodKit 单元测试(快速通道)
cd DNSPodKit && swift test

# App(macOS)
open PodDock.xcodeproj   # scheme: PodDock

# MCP 独立服务器(启动零凭据,认证走会话内 dnspod_login 工具)
cd DNSPodKit && swift run poddock-mcp
# 接入:claude mcp add --transport http poddock http://127.0.0.1:28100/mcp
# 然后让模型调用 dnspod_login 提供 "ID,Token"
```

## 开发环境(IDE 索引)

VS Code 需要一次性生成本机的 SourceKit-LSP 配置(该文件是机器本地的,已 gitignore):

```bash
brew install xcode-build-server   # 首次
scripts/setup-lsp.sh              # 生成 buildServer.json 并指向仓库内 .build/DerivedData
```

之后 Reload Window 即可获得 App 源码与 SPM 包的完整补全/跳转/诊断。改 scheme 或工程结构后重跑一次。

## 状态

开发中,当前里程碑见 [docs/PLAN.md](docs/PLAN.md)。

## LICENSE

Apache-2.0(移植自 [dnspod-api-python-web](https://github.com/likexian/dnspod-api-python-web) 的 API 参考)

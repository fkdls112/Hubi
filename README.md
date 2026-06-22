# Hub-i

[![App Store](https://img.shields.io/badge/App_Store-$7.99-blue.svg)](https://apps.apple.com/us/app/hub-i/id6774415687)
> 原生 iOS 多 AI 聊天客户端 — SwiftUI + SwiftData，零数据收集，本地优先

[![iOS](https://img.shields.io/badge/iOS-17.0+-blue.svg)](https://www.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Xcode](https://img.shields.io/badge/Xcode-26.5+-blue.svg)](https://developer.apple.com/xcode/)
[![License](https://img.shields.io/badge/License-Proprietary-red.svg)](#)

Hub-i 是一个为 iPhone / iPad 设计的多 AI 聊天客户端，支持同时接入 OpenAI、DeepSeek、Anthropic、Hermes 等多家提供商，所有对话历史和密钥仅保存在本地。

## ✨ 特性

- 🔌 **多 Provider** — OpenAI / DeepSeek / Anthropic / Hermes 自部署，统一抽象
- 💬 **流式对话** — AsyncThrowingStream + SSE 解析，支持取消
- 🎨 **Markdown 渲染** — 内联富文本 + 代码块切分 + 一键复制
- 📷 **多模态** — 图片（PhotosPicker）/ 文件（fileImporter）/ 长按录音 + STT
- 🗣️ **TTS 朗读** — 助手消息长按触发系统 TTS
- 🤖 **8 预设 Agent** — 通用 / 代码 / 翻译 / 灵感 / 学习 / 研究 / Claude / OpenClaw
- 🔍 **全文搜索** — SwiftData Predicate + snippet 高亮
- 💎 **高级版买断** — ¥49 / $7.99 一次购买，终身享有
- 🔐 **隐私优先** — 零数据收集，SwiftData + Keychain，API Key 永不离机
- 💾 **加密备份** — `.hubibackup` AES-GCM 256-bit + ShareSheet / fileImporter

## 🏗️ 架构

```
Hubi/
├── Core/
│   ├── Agents/              # AgentManager + 8 预设
│   ├── Backup/              # 导出 / 导入 + AES-GCM 加密
│   ├── Chat/                # ChatEngine + Markdown 渲染
│   ├── Entitlement/         # StoreKit 2 + 兑换码 + JWT 验签
│   ├── Models/              # SwiftData 模型 typealias
│   ├── Multimedia/          # 录音 / STT / TTS / 图片处理
│   ├── Persistence/         # ModelContainer / Keychain / Schema 迁移
│   ├── Providers/           # LLMProvider 协议 + 4 家实现 + SSEParser
│   ├── Services/            # AppLogger / HealthCheck
│   └── Utilities/           # KeySanitizer
├── Features/
│   ├── Agents/              # Agent 列表 + 编辑（含连通性测试）
│   ├── Chat/                # 聊天页（流式 / 附件 / 录音）
│   ├── Home/                # 主框架（4 标签）
│   ├── Paywall/             # Paywall + 兑换码 + FeatureGate
│   ├── Search/              # 对话全文搜索
│   └── Settings/            # 备份 / 诊断
├── Resources/
│   ├── Assets.xcassets/     # AppIcon + AccentColor
│   ├── Configuration.storekit
│   ├── Info.plist
│   ├── PrivacyInfo.xcprivacy
│   └── ProviderTemplates.json
└── HubiApp.swift            # 入口
```

## 🛠️ 技术栈

| 领域 | 技术 |
|------|------|
| UI | SwiftUI + `@Observable` (Swift 6) |
| 持久化 | SwiftData + VersionedSchema 迁移 |
| 安全 | Keychain（API Key + License）|
| 网络 | `URLSession` + AsyncThrowingStream + 自研 SSEParser |
| Markdown | `AttributedString(markdown:)` + 代码块切分 |
| 多媒体 | AVAudioRecorder / AVAudioPlayer / Speech / AVSpeechSynthesizer |
| 付费 | StoreKit 2 |
| 兑换码 | CryptoKit P-256 ES256 JWT 本地验签 |
| 备份 | AES-GCM 256-bit + SHA256×10000 KDF |
| 后端 | Cloudflare Workers + D1（兑换码服务）|
| 项目工程 | xcodegen |

## 🚀 开发

### 前置要求

- macOS 14.5+
- Xcode 26.5+（Swift 6.0+）
- xcodegen (`brew install xcodegen`)

### 生成 Xcode 工程

```bash
git clone https://github.com/fkdls112/Hubi.git
cd Hubi
bash scripts/regenerate.sh
open Hubi.xcodeproj
```

### 构建

```bash
xcodebuild build \
  -project Hubi.xcodeproj -scheme Hubi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

### 运行测试

```bash
xcodebuild test \
  -project Hubi.xcodeproj -scheme Hubi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

当前 22 个单元测试全部通过：
- `SchemaV1Tests` × 4
- `ProviderTests` × 9
- `EntitlementTests` × 5
- `JWTVerifierTests` × 2
- `BackupTests` × 2

## 💎 付费

**高级版 ¥49 / $7.99 — 一次购买，终身享有。**

- StoreKit 2 内购
- 自建兑换码（Cloudflare Workers + D1，ES256 JWT 离线验签，72h 离线缓存）

### 兑换码后端

```
POST /redeem          # 兑换 → 签发 JWT License
GET  /verify?token=  # 服务端二次验签
POST /admin/batch     # 批量发码（X-Admin-Key 鉴权）
POST /admin/revoke    # 吊销
GET  /health
```

设备绑定（默认 1 码 1 设备），幂等保证（同设备重复兑换不报错）。

## 🔐 隐私

- 不收集任何用户数据
- API Key 仅存于 iOS Keychain（`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`）
- 备份文件 **不包含 API Key**
- 兑换码后端只记录 deviceId + UA + IP（审计用，可吊销）
- `PrivacyInfo.xcprivacy` 完整声明
- 隐私政策：https://fkdls112.github.io/hubi-privacy/

## 📜 LICENSE

Proprietary — All rights reserved © 2026 Hub-i.

---

**作者**：fkdls112 · **当前版本**：v1.0.0

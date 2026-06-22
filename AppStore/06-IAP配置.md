# IAP 产品配置（1 个 · 终身买断）

> ✅ 已与 `ProductIDs.swift` + `Configuration.storekit` 交叉验证（2026-05-29）
> 💡 单一买断制：无订阅、无自动续费，过审最简单。

## 在 App Store Connect → 我的 App → 货币化 → App 内购买项目 配置

只需创建 **1 个非消耗型（Non-Consumable）** 产品，无需订阅组。

---

## 产品: 终身高级版

| 字段 | 值 |
|---|---|
| 产品 ID | `com.hubi.lifetime` |
| 类型 | 非消耗型（Non-Consumable） |
| 参考名称 | Hub-i Lifetime |
| 价格 | ¥49（价格等级按 App Store Connect 就近档位） |

**本地化（中文）**：
- 显示名称：Hub-i 终身高级版
- 描述：一次付费 ¥49，永久解锁全部预设模板与预设智能体。后续所有更新免费使用。

**本地化（英文）**：
- Display Name: Hub-i Lifetime
- Description: One-time payment, unlock all preset templates and preset agents forever. All future updates included.

---

## 免费版 vs 高级版（产品价值说明）

| 能力 | 免费版 | 高级版（¥49 终身） |
|---|---|---|
| 自定义模型（自填 baseURL/model/key） | ✅ | ✅ |
| 完整对话/语音/搜索功能 | ✅ | ✅ |
| 预设模板（OpenAI/Claude/Gemini/DeepSeek 等一键接入） | ❌ | ✅ |
| 预设智能体（翻译官/灵感写手/研究员等） | ❌ | ✅ |

> 关键：免费版功能完整，可手动配置任意模型，能力不打折。高级版卖的是"开箱即用"的便利，不是阉割免费版。

---

## 审核截图（IAP 产品需上传一张）

苹果要求该 IAP 产品上传一张展示其 App 内位置的截图（必须看到产品名 + 价格）。

- 直接用 Paywall 截图 `screenshots/06-paywall.png`
- 尺寸：1290×2796 (iPhone 6.7") 或 1320×2868 (iPhone 6.9")
- 格式：PNG 或 JPG

---

## ProductIDs 真值来源（已验证）

`Hubi/Core/Entitlement/ProductIDs.swift`:
```swift
static let lifetime = "com.hubi.lifetime"
static let all: Set<String> = [lifetime]
```

`Hubi/Resources/Configuration.storekit` 仅含 1 个 NonConsumable 产品，`subscriptionGroups` 为空数组，与上述完全一致 ✓

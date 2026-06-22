import Foundation
import SwiftData

/// 预设 Agent + CRUD 辅助
enum AgentManager {

    /// App 首启时插入预设（如果库为空）
    @MainActor
    static func seedIfEmpty(context: ModelContext) {
        // 先清掉历史遗留的含本地 IP 的 Agent（一次性迁移）
        cleanupLocalLeaks(context: context)

        let count = (try? context.fetchCount(FetchDescriptor<Agent>())) ?? 0
        guard count == 0 else { return }

        for preset in presets() {
            let a = Agent(
                name: preset.name,
                providerKey: preset.providerKey,
                baseURL: preset.baseURL,
                model: preset.model
            )
            a.systemPrompt = preset.systemPrompt
            a.avatarSymbol = preset.icon
            a.tintColor = preset.tint
            a.requiredTier = preset.tier
            context.insert(a)
        }
        try? context.save()
        AppLogger.shared.info("已植入 \(presets().count) 个预设 Agent")
    }

    /// 清掉历史预设里残留的本地 IP / 已废弃的 Agent
    @MainActor
    static func cleanupLocalLeaks(context: ModelContext) {
        let deprecatedNames: Set<String> = [
            "代码大师", "Claude 思考者", "OpenClaw 自动化"
        ]
        guard let all = try? context.fetch(FetchDescriptor<Agent>()) else { return }
        var removed = 0
        for a in all {
            let leaks = a.baseURL.contains("192.168.") || a.baseURL.contains("127.0.0.1") || a.baseURL.contains("localhost")
            if deprecatedNames.contains(a.name) || leaks {
                context.delete(a)
                removed += 1
            }
        }
        if removed > 0 {
            try? context.save()
            AppLogger.shared.info("清理了 \(removed) 个含本地信息或已废弃的 Agent")
        }
    }

    struct Preset {
        let name: String
        let providerKey: String
        let baseURL: String
        let model: String
        let systemPrompt: String
        let icon: String
        let tint: String
        let tier: String
    }

    static func presets() -> [Preset] {
        [
            .init(name: "通用助手", providerKey: "openai",
                  baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini",
                  systemPrompt: "你是一个友好、务实的中文助手，回答简洁直接。",
                  icon: "sparkle", tint: "#7B61FF", tier: "premium"),
            .init(name: "翻译官", providerKey: "openai",
                  baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini",
                  systemPrompt: "你是中英互译专家。用户给中文返回英文，反之亦然。仅输出译文。",
                  icon: "character.bubble", tint: "#FF9500", tier: "premium"),
            .init(name: "灵感写手", providerKey: "openai",
                  baseURL: "https://api.openai.com/v1", model: "gpt-4o",
                  systemPrompt: "你是创意写作助手，擅长头脑风暴、文案润色、起标题。",
                  icon: "lightbulb", tint: "#FFD60A", tier: "premium"),
            .init(name: "学习伙伴", providerKey: "deepseek",
                  baseURL: "https://api.deepseek.com/v1", model: "deepseek-chat",
                  systemPrompt: "你是一位耐心的家教，用最简单的语言由浅入深讲解任何知识。",
                  icon: "book", tint: "#2F6BFF", tier: "premium"),
            .init(name: "深度研究员", providerKey: "deepseek",
                  baseURL: "https://api.deepseek.com/v1", model: "deepseek-reasoner",
                  systemPrompt: "你是研究分析师，擅长结构化拆解问题、推理、证据链。",
                  icon: "magnifyingglass", tint: "#6E56CF", tier: "premium"),
        ]
    }
}

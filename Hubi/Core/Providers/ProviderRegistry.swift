import Foundation
import Observation

@MainActor
@Observable
final class ProviderRegistry {
    static let shared = ProviderRegistry()

    private(set) var providers: [String: any LLMProvider] = [:]
    private(set) var templates: [ProviderTemplate] = []

    private init() {
        register(OpenAIProvider.openAI)
        register(OpenAIProvider.deepseek)
        register(OpenAIProvider.hermes)
        register(AnthropicProvider())
        loadTemplates()
    }

    func register(_ provider: any LLMProvider) {
        providers[provider.key] = provider
    }

    func provider(for key: String) -> (any LLMProvider)? {
        providers[key]
    }

    private func loadTemplates() {
        guard let url = Bundle.main.url(forResource: "ProviderTemplates", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            AppLogger.shared.warning("ProviderTemplates.json 未找到")
            return
        }
        do {
            templates = try JSONDecoder().decode([ProviderTemplate].self, from: data)
            AppLogger.shared.info("加载 \(templates.count) 个 Provider 模板")
        } catch {
            AppLogger.shared.error("ProviderTemplates 解析失败: \(error)")
        }
    }
}

struct ProviderTemplate: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let providerKey: String
    let defaultBaseURL: String
    let defaultModel: String
    let description: String
    let icon: String
    let tintColor: String
    let requiredTier: String
}

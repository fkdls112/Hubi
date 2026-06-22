import SwiftUI
import SwiftData

@main
struct HubiApp: App {
    let modelContainer: ModelContainer
    @State private var logger = AppLogger.shared
    @State private var entitlementStore = EntitlementStore.shared

    init() {
        do {
            let container = try ModelContainer.hubi()
            self.modelContainer = container
            Task.detached {
                await HealthCheck.run(container: container)
            }
            Task { @MainActor in
                await StoreKitManager.shared.loadProducts()
                await StoreKitManager.shared.refreshEntitlement()
            }
#if DEBUG
            Task { @MainActor in
                await seedDefaultAgents(container: container)
            }
#endif
        } catch {
            fatalError("Failed to init ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(modelContainer)
                .environment(logger)
                .environment(entitlementStore)
        }
    }
}

#if DEBUG
@MainActor
private func seedDefaultAgents(container: ModelContainer) {
    let defaultsKey = "hubi.defaultAgentsSeeded"
    guard !UserDefaults.standard.bool(forKey: defaultsKey) else { return }
    UserDefaults.standard.set(true, forKey: defaultsKey)

    let context = container.mainContext

    let agents: [(name: String, providerKey: String, baseURL: String, model: String, apiKey: String?, symbol: String, color: String)] = [
        (
            "DeepSeek",
            "deepseek",
            "https://api.deepseek.com/v1",
            "deepseek-chat",
            "sk-your-deepseek-key-here",
            "brain.head.profile",
            "#4D6BFE"
        ),
        (
            "Gemini",
            "openai",
            "https://generativelanguage.googleapis.com/v1beta/openai",
            "gemini-2.5-flash",
            "AIzaSyAivAKkzX4lFINwk0V5ZzWZ9t71YPmBgkA",
            "sparkle",
            "#FF9500"
        ),
        (
            "Hermes",
            "hermes",
            "http://192.168.2.108:8642/v1",
            "hermes-agent",
            "hermes-agent-chat-2026",
            "server.rack",
            "#5856D6"
        ),
    ]

    for a in agents {
        let agent = Agent(name: a.name, providerKey: a.providerKey, baseURL: a.baseURL, model: a.model)
        agent.avatarSymbol = a.symbol
        agent.tintColor = a.color
        context.insert(agent)
        try? context.save()
        // Keychain 写入 API Key
        agent.apiKey = a.apiKey
    }

    AppLogger.shared.info("Seeded \(agents.count) default agents")
}
#endif

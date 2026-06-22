import Foundation
import SwiftData

enum HealthCheck {
    /// 启动时跑：清理孤儿 Keychain 条目（Agent 已删但 Keychain 中残留 hubi.agent.<UUID>）
    static func run(container: ModelContainer) async {
        await MainActor.run {
            let context = ModelContext(container)
            do {
                let agents = try context.fetch(FetchDescriptor<Agent>())
                let validKeys = Set(agents.map { "hubi.agent.\($0.id)" })

                let allAccounts = KeychainStore.shared.listAllAccounts()
                var cleaned = 0
                for account in allAccounts where account.hasPrefix("hubi.agent.") {
                    if !validKeys.contains(account) {
                        KeychainStore.shared.write(key: account, value: nil)
                        cleaned += 1
                    }
                }
                if cleaned > 0 {
                    AppLogger.shared.info("HealthCheck cleaned \(cleaned) orphan keychain entries")
                } else {
                    AppLogger.shared.info("HealthCheck: no orphans found")
                }
            } catch {
                AppLogger.shared.error("HealthCheck failed: \(error)")
            }
        }
    }
}

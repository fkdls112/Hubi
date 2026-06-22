import Foundation
import Observation

@MainActor
@Observable
final class EntitlementStore {
    static let shared = EntitlementStore()

    private(set) var iapEntitlement: Entitlement = .none

    private let cacheKey = "hubi.entitlement.cache.v2"

    private init() {
        loadCache()
    }

    var current: Entitlement { iapEntitlement }
    var currentTier: HubiTier { current.tier }

    func updateIAP(_ entitlement: Entitlement) {
        iapEntitlement = entitlement
        saveCache()
        AppLogger.shared.info("IAP entitlement: \(entitlement.tier)")
    }

    func clearAll() {
        iapEntitlement = .none
        saveCache()
    }

    // MARK: - 持久化

    private func saveCache() {
        if let data = try? JSONEncoder().encode(iapEntitlement) {
            try? KeychainStore.shared.write(key: cacheKey, value: data.base64EncodedString())
        }
    }

    private func loadCache() {
        guard let str = try? KeychainStore.shared.read(key: cacheKey),
              let data = Data(base64Encoded: str),
              let cache = try? JSONDecoder().decode(Entitlement.self, from: data) else { return }
        iapEntitlement = cache
        AppLogger.shared.info("Restored entitlement cache")
    }
}

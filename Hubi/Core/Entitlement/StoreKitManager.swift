import Foundation
import StoreKit
import Observation

@MainActor
@Observable
final class StoreKitManager {
    static let shared = StoreKitManager()

    private(set) var products: [Product] = []
    private(set) var purchaseInProgress: Bool = false
    private(set) var lastError: String?
    private var transactionListener: Task<Void, Error>?

    private init() {
        startTransactionListener()
        Task { await loadProducts() }
        Task { await refreshEntitlement() }
    }

    deinit {
        // transactionListener cancelation handled by app lifecycle / Task cancellation
    }

    // MARK: - 产品加载
    func loadProducts() async {
        do {
            let fetched = try await Product.products(for: HubiProduct.all)
            // 排序: lifetime 优先
            self.products = fetched.sorted { lhs, rhs in
                productSortKey(lhs.id) > productSortKey(rhs.id)
            }
            AppLogger.shared.info("StoreKit loaded \(fetched.count) products")
        } catch {
            lastError = "产品加载失败: \(error.localizedDescription)"
            AppLogger.shared.error("StoreKit load failed: \(error)")
        }
    }

    private func productSortKey(_ id: String) -> Int {
        id == HubiProduct.lifetime ? 100 : 0
    }

    // MARK: - 购买
    func purchase(_ product: Product) async -> PurchaseResult {
        purchaseInProgress = true
        defer { purchaseInProgress = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlement()
                return .success
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed("未知结果")
            }
        } catch {
            lastError = error.localizedDescription
            return .failed(error.localizedDescription)
        }
    }

    enum PurchaseResult {
        case success, cancelled, pending, failed(String)
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    // MARK: - 兑换码（Apple Offer Code Sheet）
    func presentOfferCodeRedemption() async {
        do {
            try await AppStore.presentOfferCodeRedeemSheet(in: UIApplication.shared.activeWindowScene ?? UIWindow().windowScene!)
        } catch {
            AppLogger.shared.error("Offer code sheet 失败: \(error)")
        }
    }

    // MARK: - Entitlement 刷新（遍历当前生效凭据）
    func refreshEntitlement() async {
        var bestTier: HubiTier = .free
        var bestProductID: String? = nil
        var bestExpires: Date? = nil

        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result else { continue }
            let tier = HubiProduct.tier(for: tx.productID)
            if tier > bestTier
                || (tier == bestTier && (tx.expirationDate ?? .distantFuture) > (bestExpires ?? .distantPast)) {
                bestTier = tier
                bestProductID = tx.productID
                bestExpires = tx.expirationDate
            }
        }

        let ent = Entitlement(
            tier: bestTier,
            source: .iap,
            productID: bestProductID,
            expiresAt: bestExpires,
            grantedAt: Date()
        )
        EntitlementStore.shared.updateIAP(ent)
    }

    // MARK: - 交易监听
    private func startTransactionListener() {
        transactionListener = Task.detached {
            for await result in Transaction.updates {
                if case .verified(let tx) = result {
                    await tx.finish()
                    await StoreKitManager.shared.refreshEntitlement()
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe): return safe
        case .unverified(_, let error): throw error
        }
    }
}

extension UIApplication {
    var activeWindowScene: UIWindowScene? {
        connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }
}

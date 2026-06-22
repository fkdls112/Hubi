import XCTest
@testable import Hubi

final class EntitlementTests: XCTestCase {
    func testTierComparable() {
        XCTAssertTrue(HubiTier.free < .premium)
        XCTAssertFalse(HubiTier.premium < .free)
    }

    func testTierParseLegacy() {
        // 旧档位值一律映射到 premium，兼容历史数据
        XCTAssertEqual(HubiTier.parse("plus"), .premium)
        XCTAssertEqual(HubiTier.parse("pro"), .premium)
        XCTAssertEqual(HubiTier.parse("lifetime"), .premium)
        XCTAssertEqual(HubiTier.parse("premium"), .premium)
        XCTAssertEqual(HubiTier.parse("free"), .free)
        XCTAssertEqual(HubiTier.parse("garbage"), .free)
    }

    func testProductIDsTier() {
        XCTAssertEqual(HubiProduct.tier(for: HubiProduct.lifetime), .premium)
        XCTAssertEqual(HubiProduct.tier(for: "unknown"), .free)
    }

    func testEntitlementIsActive() {
        let lifetime = Entitlement(tier: .premium, source: .iap, productID: HubiProduct.lifetime,
                                    expiresAt: nil, deviceBound: nil, grantedAt: Date())
        XCTAssertTrue(lifetime.isActive)

        let expired = Entitlement(tier: .premium, source: .iap, productID: HubiProduct.lifetime,
                                  expiresAt: Date().addingTimeInterval(-3600),
                                  deviceBound: nil, grantedAt: Date())
        XCTAssertFalse(expired.isActive)

        let none = Entitlement.none
        XCTAssertFalse(none.isActive)
    }

    @MainActor
    func testEntitlementStoreMerging() {
        let store = EntitlementStore.shared
        store.clearAll()
        XCTAssertEqual(store.currentTier, .free)

        // IAP 终身买断
        let iap = Entitlement(tier: .premium, source: .iap, productID: HubiProduct.lifetime,
                              expiresAt: nil, deviceBound: nil, grantedAt: Date())
        store.updateIAP(iap)
        XCTAssertEqual(store.currentTier, .premium)
        store.clearAll()

        // 兑换码授予 premium
        let redeem = Entitlement(tier: .premium, source: .redeem, productID: nil,
                                 expiresAt: Date().addingTimeInterval(86400 * 30),
                                 deviceBound: "dev1", grantedAt: Date())
        store.updateRedeem(redeem)
        XCTAssertEqual(store.currentTier, .premium)
        store.clearAll()
    }
}

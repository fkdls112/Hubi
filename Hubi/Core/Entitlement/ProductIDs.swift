import Foundation

/// 单一买断制：免费版 vs 高级版（一次性 ¥49 终身解锁）。
enum HubiProduct {
    static let lifetime = "com.hubi.lifetime.v1"

    static let all: Set<String> = [lifetime]

    /// 购买终身产品即授予 premium 档。
    static func tier(for productID: String) -> HubiTier {
        all.contains(productID) ? .premium : .free
    }
}

import Foundation

/// 两档会员模型：免费版 / 高级版。
/// 高级版（含订阅与终身）解锁全部预设模板；免费版只能使用自定义模板。
enum HubiTier: String, Codable, Comparable, Sendable, CaseIterable {
    case free
    case premium

    private var rank: Int {
        switch self {
        case .free:    return 0
        case .premium: return 1
        }
    }

    static func < (lhs: HubiTier, rhs: HubiTier) -> Bool { lhs.rank < rhs.rank }

    var displayName: String {
        switch self {
        case .free:    return "免费版"
        case .premium: return "高级版"
        }
    }

    /// 兼容旧值（plus/pro/lifetime 一律视为 premium），未知值回退 free。
    static func parse(_ raw: String) -> HubiTier {
        switch raw {
        case "premium", "plus", "pro", "lifetime": return .premium
        case "free":                                return .free
        default:                                     return .free
        }
    }
}

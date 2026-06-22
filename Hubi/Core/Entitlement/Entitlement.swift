import Foundation

struct Entitlement: Codable, Sendable {
    var tier: HubiTier
    var source: Source
    var productID: String?
    var expiresAt: Date?
    var grantedAt: Date

    enum Source: String, Codable, Sendable {
        case iap, none
    }

    static let none = Entitlement(tier: .free, source: .none, productID: nil,
                                  expiresAt: nil, grantedAt: Date())

    var isActive: Bool {
        if let exp = expiresAt { return exp > Date() }
        return tier != .free
    }
}

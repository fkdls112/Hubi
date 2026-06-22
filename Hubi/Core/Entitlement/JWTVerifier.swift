import Foundation
import CryptoKit
import Security

/// 极简 ES256 (P-256) JWT 本地验签
enum JWTVerifier {

    struct Claims: Decodable {
        let iss: String?
        let sub: String?         // deviceID
        let aud: String?
        let jti: String?
        let iat: Int64?
        let exp: Int64?
        let tier: String
        let code: String?
        let features: [String]?
    }

    enum VerifyError: Error {
        case malformed, badSignature, decodeError, badKey
    }

    static func verifyES256(token: String, pemPublicKey: String) throws -> Claims {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { throw VerifyError.malformed }
        let headerB = String(parts[0])
        let payloadB = String(parts[1])
        let sigB = String(parts[2])

        let signedData = Data("\(headerB).\(payloadB)".utf8)
        guard let sigRaw = Data(base64URLEncoded: sigB) else { throw VerifyError.malformed }
        // JWS ES256: signature is r||s raw 64 bytes; CryptoKit P256.Signing accepts rawRepresentation directly
        guard sigRaw.count == 64 else { throw VerifyError.malformed }

        let key = try Self.loadPublicKey(pem: pemPublicKey)
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: sigRaw)
        let digest = SHA256.hash(data: signedData)
        guard key.isValidSignature(signature, for: digest) else { throw VerifyError.badSignature }

        guard let payloadData = Data(base64URLEncoded: payloadB) else { throw VerifyError.decodeError }
        return try JSONDecoder().decode(Claims.self, from: payloadData)
    }

    /// 解析 SPKI/PEM 公钥
    static func loadPublicKey(pem: String) throws -> P256.Signing.PublicKey {
        // 优先用 CryptoKit 直接读 PEM (iOS 14+ 支持 X9.63 / SEC1)
        if let key = try? P256.Signing.PublicKey(pemRepresentation: pem) {
            return key
        }
        // 回退：手工剥头，去 base64，DER -> SubjectPublicKeyInfo 末尾 65 字节是 04||X||Y
        let stripped = pem
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let der = Data(base64Encoded: stripped) else { throw VerifyError.badKey }
        // 取末尾 65 字节作为 X9.63 表示
        guard der.count >= 65 else { throw VerifyError.badKey }
        let x963 = der.suffix(65)
        return try P256.Signing.PublicKey(x963Representation: x963)
    }
}

extension Data {
    init?(base64URLEncoded: String) {
        var s = base64URLEncoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        self.init(base64Encoded: s)
    }
}

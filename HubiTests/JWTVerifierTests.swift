import XCTest
@testable import Hubi

final class JWTVerifierTests: XCTestCase {
    func testMalformedToken() {
        XCTAssertThrowsError(try JWTVerifier.verifyES256(token: "abc", pemPublicKey: RedemptionService.publicPEM))
        XCTAssertThrowsError(try JWTVerifier.verifyES256(token: "abc.def", pemPublicKey: RedemptionService.publicPEM))
    }

    func testPublicKeyLoad() throws {
        _ = try JWTVerifier.loadPublicKey(pem: RedemptionService.publicPEM)
    }
}

import XCTest
@testable import ADBKit

final class ADBPairingCryptoTests: XCTestCase {
    func testPairingProviderUsesTheNativeAospCryptoBoundary() throws {
        let provider = AOSPWiFiPairingProvider()
        if AOSPBoringSSLPairingEngine.isAvailable {
            let engine = try provider.makeCryptoEngine(code: "123456")
            XCTAssertFalse(engine.localMessage.isEmpty)
        } else {
            XCTAssertThrowsError(try provider.makeCryptoEngine(code: "123456")) { error in
                guard case ADBError.pairingUnavailable = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }
        }
    }

    func testEmptyPairingCodeIsRejectedBeforeNativeCall() {
        XCTAssertThrowsError(try AOSPBoringSSLPairingEngine(password: Data())) { error in
            guard case ADBError.invalidArgument("pairing code") = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testAospClientAndServerDeriveTheSameAuthenticatedCipher() throws {
        guard AOSPBoringSSLPairingEngine.isAvailable else { return }
        let password = Data("123456".utf8)
        let client = try AOSPBoringSSLPairingEngine(password: password, role: .client)
        let server = try AOSPBoringSSLPairingEngine(password: password, role: .server)
        try client.process(peerMessage: server.localMessage)
        try server.process(peerMessage: client.localMessage)
        let plaintext = Data("ADBKit pairing proof".utf8)
        let ciphertext = try client.encrypt(plaintext)
        XCTAssertEqual(try server.decrypt(ciphertext), plaintext)
    }
}

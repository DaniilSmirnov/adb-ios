import Foundation
import Security

public protocol ADBPairingProvider: Sendable {
    func pair(code: String, device: ADBDevice) async throws
}

/// Key storage is deliberately isolated from the protocol implementation. Pairing
/// cryptography must use the AOSP/BoringSSL implementation in the production app;
/// this package never invents a replacement algorithm.
public final class KeychainADBKeyStore: @unchecked Sendable {
    private let service = "com.daniilsmirnov.adb-ios.adb"
    public init() {}
    public func save(publicKey: Data, privateKey: Data, account: String = "default") throws {
        for (data, label) in [(publicKey, "public"), (privateKey, "private")] {
            let query: [String: Any] = [kSecClass as String: kSecClassKey, kSecAttrService as String: service, kSecAttrAccount as String: "\(account).\(label)", kSecValueData as String: data]
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess || status == errSecDuplicateItem else { throw ADBError.protocolError("Keychain error \(status)") }
        }
    }
}

public struct AOSPWiFiPairingProvider: ADBPairingProvider {
    public init() {}
    public func pair(code: String, device: ADBDevice) async throws {
        guard !code.isEmpty else { throw ADBError.invalidArgument("pairing code") }
        throw ADBError.pairingUnavailable
    }
}


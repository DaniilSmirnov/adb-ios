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

    public func loadPublicKey(account: String = "default") throws -> Data? { try load(label: "public", account: account) }
    public func loadPrivateKey(account: String = "default") throws -> Data? { try load(label: "private", account: account) }
    public func delete(account: String = "default") throws {
        for label in ["public", "private"] {
            let query: [String: Any] = [kSecClass as String: kSecClassKey, kSecAttrService as String: service, kSecAttrAccount as String: "\(account).\(label)"]
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw ADBError.protocolError("Keychain error \(status)") }
        }
    }

    private func load(label: String, account: String) throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassKey, kSecAttrService as String: service, kSecAttrAccount as String: "\(account).\(label)", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw ADBError.protocolError("Keychain error \(status)") }
        return result as? Data
    }
}

#if canImport(Security)
import Security

/// A Keychain-backed ADB AUTH provider. The public key is encoded in the
/// Android RSAPublicKey wire format; no custom cryptography is used for the
/// signature operation.
public final class KeychainADBAuthenticator: ADBAuthenticator, @unchecked Sendable {
    private let store: KeychainADBKeyStore
    private let account: String
    public init(store: KeychainADBKeyStore = KeychainADBKeyStore(), account: String = "default") { self.store = store; self.account = account }

    public func signature(for token: Data) async throws -> Data? {
        let privateData = try ensureKey().privateKey
        guard let key = SecKeyCreateWithData(privateData as CFData, [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPrivate] as CFDictionary, nil) else { throw ADBError.authenticationFailed }
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA1, token as CFData, &error) else { throw ADBError.authenticationFailed }
        return signature as Data
    }

    public func publicKey() async throws -> Data? { try ensureKey().wirePublicKey }

    private func ensureKey() throws -> (privateKey: Data, wirePublicKey: Data) {
        if let privateKey = try store.loadPrivateKey(account: account), let publicKey = try store.loadPublicKey(account: account) {
            return (privateKey, try ADBAndroidPublicKeyEncoder.encode(der: publicKey))
        }
        var error: Unmanaged<CFError>?
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048, kSecPrivateKeyAttrs: [kSecAttrIsPermanent: false]]
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error), let publicKey = SecKeyCopyPublicKey(privateKey),
              let privateData = SecKeyCopyExternalRepresentation(privateKey, &error) as Data?, let publicData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else { throw ADBError.authenticationFailed }
        try store.save(publicKey: publicData, privateKey: privateData, account: account)
        return (privateData, try ADBAndroidPublicKeyEncoder.encode(der: publicData))
    }
}

private enum ADBAndroidPublicKeyEncoder {
    static func encode(der: Data) throws -> Data {
        let (modulus, exponent) = try parseRSAPublicKey(der)
        guard modulus.count == 256 else { throw ADBError.unsupported("ADB AUTH requires a 2048-bit RSA key") }
        var n = Array(repeating: UInt32(0), count: 64)
        for (index, byte) in modulus.reversed().enumerated() { n[index / 4] |= UInt32(byte) << UInt32((index % 4) * 8) }
        let n0inv = 0 &- inverseMod32(n[0])
        var rr = Array(repeating: UInt32(0), count: 64); rr[0] = 1
        for _ in 0..<4096 { doubleMod(&rr, modulus: n) }
        var data = Data(); append(&data, 64); append(&data, n0inv)
        n.forEach { append(&data, $0) }; rr.forEach { append(&data, $0) }; append(&data, UInt32(exponent))
        let encoded = data.base64EncodedString()
        return Data((encoded + " DeviceManager@iOS").utf8)
    }

    private static func parseRSAPublicKey(_ data: Data) throws -> (Data, UInt64) {
        let bytes = [UInt8](data); var index = 0
        func length() throws -> Int { guard index < bytes.count else { throw ADBError.invalidPacket }; let first = bytes[index]; index += 1; if first < 0x80 { return Int(first) }; let count = Int(first & 0x7f); guard count > 0, count <= 4, index + count <= bytes.count else { throw ADBError.invalidPacket }; var value = 0; for _ in 0..<count { value = value * 256 + Int(bytes[index]); index += 1 }; return value }
        guard bytes[index] == 0x30 else { throw ADBError.invalidPacket }; index += 1; _ = try length(); guard bytes[index] == 0x02 else { throw ADBError.invalidPacket }; index += 1; let modulusLength = try length(); guard index + modulusLength <= bytes.count else { throw ADBError.invalidPacket }; var modulus = Data(bytes[index..<(index + modulusLength)]); index += modulusLength; if modulus.first == 0 { modulus.removeFirst() }; guard bytes[index] == 0x02 else { throw ADBError.invalidPacket }; index += 1; let exponentLength = try length(); guard exponentLength > 0, exponentLength <= 8, index + exponentLength <= bytes.count else { throw ADBError.invalidPacket }; var exponent: UInt64 = 0; for byte in bytes[index..<(index + exponentLength)] { exponent = (exponent << 8) | UInt64(byte) }; return (modulus, exponent)
    }

    private static func inverseMod32(_ value: UInt32) -> UInt32 { var result: UInt32 = 1; for _ in 0..<5 { result = result &* (2 &- value &* result) }; return result }
    private static func doubleMod(_ value: inout [UInt32], modulus: [UInt32]) { var carry: UInt32 = 0; for index in 0..<value.count { let next = value[index] >> 31; value[index] = (value[index] << 1) | carry; carry = next }; if carry != 0 || value.lexicographicallyPrecedes(modulus) == false { var borrow: UInt64 = 0; for index in 0..<value.count { let sub = UInt64(modulus[index]) + borrow; let current = UInt64(value[index]); value[index] = UInt32(truncatingIfNeeded: current &- sub); borrow = current < sub ? 1 : 0 } } }
    private static func append(_ data: inout Data, _ value: UInt32) { var little = value.littleEndian; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
}
#endif

public struct AOSPWiFiPairingProvider: ADBPairingProvider {
    public init() {}
    public func makeCryptoEngine(code: String) throws -> any ADBPairingCryptoEngine {
        try AOSPBoringSSLPairingEngine(password: Data(code.utf8))
    }
    public func pair(code: String, device: ADBDevice) async throws {
        _ = try makeCryptoEngine(code: code)
        throw ADBError.pairingUnavailable
    }
}

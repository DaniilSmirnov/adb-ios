import Foundation
import ADBPairingNative

public protocol ADBPairingCryptoEngine: AnyObject, Sendable {
    var localMessage: Data { get }
    func process(peerMessage: Data) throws
    func encrypt(_ plaintext: Data) throws -> Data
    func decrypt(_ ciphertext: Data) throws -> Data
}

public enum ADBPairingCryptoRole: Sendable {
    case client
    case server
}

/// AOSP-compatible SPAKE2 + HKDF-SHA256 + AES-128-GCM pairing crypto.
///
/// The implementation is delegated to the pinned BoringSSL build configured
/// through `ADBKIT_BORINGSSL_ROOT`; the Swift package contains no replacement
/// cryptographic implementation.
public final class AOSPBoringSSLPairingEngine: ADBPairingCryptoEngine, @unchecked Sendable {
    public static var isAvailable: Bool { adb_pairing_boringssl_available() == 1 }

    public let localMessage: Data
    private let lock = NSLock()
    private var context: OpaquePointer?

    public convenience init(password: Data) throws {
        try self.init(password: password, role: .client)
    }

    public init(password: Data, role: ADBPairingCryptoRole) throws {
        guard !password.isEmpty else { throw ADBError.invalidArgument("pairing code") }
        guard Self.isAvailable else { throw ADBError.pairingUnavailable }
        var message = [UInt8](repeating: 0, count: 32)
        var messageLength = message.count
        let created: OpaquePointer? = password.withUnsafeBytes { bytes in
            let baseAddress = bytes.bindMemory(to: UInt8.self).baseAddress
            switch role {
            case .client:
                return adb_pairing_crypto_client_new(baseAddress, password.count, &message,
                                                     &messageLength, message.count)
            case .server:
                return adb_pairing_crypto_server_new(baseAddress, password.count, &message,
                                                     &messageLength, message.count)
            }
        }
        guard let created, messageLength > 0 else { throw ADBError.authenticationFailed }
        context = created
        localMessage = Data(message.prefix(messageLength))
    }

    deinit {
        if let context { adb_pairing_crypto_destroy(context) }
    }

    public func process(peerMessage: Data) throws {
        guard !peerMessage.isEmpty else { throw ADBError.invalidPacket }
        lock.lock(); defer { lock.unlock() }
        guard let context else { throw ADBError.connectionClosed }
        let success = peerMessage.withUnsafeBytes { bytes in
            adb_pairing_crypto_process(context, bytes.bindMemory(to: UInt8.self).baseAddress,
                                        peerMessage.count)
        }
        guard success == 1 else { throw ADBError.authenticationFailed }
    }

    public func encrypt(_ plaintext: Data) throws -> Data {
        try crypt(plaintext, encrypt: true)
    }

    public func decrypt(_ ciphertext: Data) throws -> Data {
        try crypt(ciphertext, encrypt: false)
    }

    private func crypt(_ input: Data, encrypt: Bool) throws -> Data {
        guard !input.isEmpty else { throw ADBError.invalidArgument("pairing payload") }
        lock.lock(); defer { lock.unlock() }
        guard let context else { throw ADBError.connectionClosed }
        let capacity = encrypt ? max(input.count + 16, input.count) : input.count
        var output = [UInt8](repeating: 0, count: capacity)
        var outputLength = 0
        let success = input.withUnsafeBytes { bytes in
            output.withUnsafeMutableBufferPointer { buffer in
                if encrypt {
                    return adb_pairing_crypto_encrypt(context, bytes.bindMemory(to: UInt8.self).baseAddress,
                                                      input.count, buffer.baseAddress, buffer.count,
                                                      &outputLength)
                }
                return adb_pairing_crypto_decrypt(context, bytes.bindMemory(to: UInt8.self).baseAddress,
                                                  input.count, buffer.baseAddress, buffer.count,
                                                  &outputLength)
            }
        }
        guard success == 1 else { throw ADBError.authenticationFailed }
        return Data(output.prefix(outputLength))
    }
}

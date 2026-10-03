import Foundation

public struct ADBDevice: Identifiable, Hashable, Sendable {
    public let id: String
    public let host: String
    public let port: UInt16
    public let model: String?
    public let transport: TransportKind

    public init(id: String, host: String, port: UInt16 = 5555, model: String? = nil,
                transport: TransportKind = .tcp) {
        self.id = id; self.host = host; self.port = port; self.model = model; self.transport = transport
    }
}

public enum TransportKind: String, Sendable { case tcp, tls, wifiPairing }

public enum ADBError: Error, LocalizedError, Sendable {
    case invalidPacket, protocolError(String), connectionClosed, timeout
    case authenticationRequired, authenticationFailed, pairingUnavailable
    case commandFailed(String), invalidArgument(String), unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPacket: return "Invalid ADB packet"
        case .protocolError(let value): return "ADB protocol error: \(value)"
        case .connectionClosed: return "ADB connection closed"
        case .timeout: return "ADB operation timed out"
        case .authenticationRequired: return "ADB authentication is required"
        case .authenticationFailed: return "ADB authentication failed"
        case .pairingUnavailable: return "ADB pairing is unavailable on this device"
        case .commandFailed(let value): return value
        case .invalidArgument(let value): return "Invalid argument: \(value)"
        case .unsupported(let value): return "Unsupported: \(value)"
        }
    }
}

public struct ADBCommandResult: Sendable {
    public let output: String
    public let exitCode: Int32?
    public init(output: String, exitCode: Int32? = nil) { self.output = output; self.exitCode = exitCode }
}


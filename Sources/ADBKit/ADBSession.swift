import Foundation

public protocol ADBAuthenticator: Sendable {
    func signature(for token: Data) async throws -> Data?
    func publicKey() async throws -> Data?
}

public struct NoopADBAuthenticator: ADBAuthenticator {
    public init() {}
    public func signature(for token: Data) async throws -> Data? { nil }
    public func publicKey() async throws -> Data? { nil }
}

/// A direct adbd session. It deliberately speaks to the device socket and never
/// routes through a local adb server.
public final class ADBSession: @unchecked Sendable {
    private let transport: ADBByteTransport
    private let authenticator: ADBAuthenticator
    private var readBuffer = Data()
    private var nextLocalID: UInt32 = 1
    private var connected = false
    private var maxPayload = 4096

    public init(transport: ADBByteTransport, authenticator: ADBAuthenticator = NoopADBAuthenticator()) {
        self.transport = transport; self.authenticator = authenticator
    }

    public func connect() async throws {
        guard !connected else { return }
        try await send(ADBMessage(command: .cnxn, arg0: 0x01000000, arg1: UInt32(maxPayload), payload: Data("host::DeviceManager\0".utf8)))
        while true {
            let message = try await receive()
            switch message.command {
            case .cnxn:
                maxPayload = max(1024, Int(message.arg1))
                connected = true
                return
            case .auth:
                guard message.arg0 == 1 else { throw ADBError.authenticationFailed }
                if let signature = try await authenticator.signature(for: message.payload) {
                    try await send(ADBMessage(command: .auth, arg0: 2, payload: signature))
                } else if let publicKey = try await authenticator.publicKey() {
                    try await send(ADBMessage(command: .auth, arg0: 3, payload: publicKey + Data([0])))
                } else {
                    throw ADBError.authenticationRequired
                }
            default:
                throw ADBError.protocolError("expected CNXN, received \(message.command.name)")
            }
        }
    }

    public func close() { transport.close(); connected = false }

    public func shell(_ command: String) async throws -> ADBCommandResult {
        let stream = try await open("shell:\(command)\0")
        var output = Data()
        while true {
            let message = try await receive()
            guard message.arg0 == stream.remoteID || message.command == .clse else { continue }
            switch message.command {
            case .wrte:
                output.append(message.payload)
                try await send(ADBMessage(command: .okay, arg0: stream.localID, arg1: stream.remoteID))
            case .clse:
                try await send(ADBMessage(command: .clse, arg0: stream.localID, arg1: stream.remoteID))
                return ADBCommandResult(output: String(decoding: output, as: UTF8.self))
            default: break
            }
        }
    }

    public func push(file: URL, remotePath: String, mode: UInt32 = 0o644) async throws {
        guard FileManager.default.fileExists(atPath: file.path) else { throw ADBError.invalidArgument("APK does not exist") }
        let stream = try await open("sync:\0")
        let destination = Data("\(remotePath),\(mode)\0".utf8)
        try await writeSync(Data("SEND".utf8) + destination, stream: stream)
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        while true {
            let chunk = try handle.read(upToCount: max(1024, min(maxPayload, 64 * 1024))) ?? Data()
            if chunk.isEmpty { break }
            try await writeSync(Data("DATA".utf8) + littleEndian(UInt32(chunk.count)) + chunk, stream: stream)
        }
        let timestamp = UInt32(Date().timeIntervalSince1970)
        try await writeSync(Data("DONE".utf8) + littleEndian(timestamp), stream: stream)
        let response = try await receiveSyncResponse(stream: stream)
        if response.code == "FAIL" { throw ADBError.commandFailed(String(decoding: response.payload, as: UTF8.self)) }
        guard response.code == "OKAY" else { throw ADBError.protocolError("sync \(response.code)") }
        try await close(stream)
    }

    private struct Stream { let localID: UInt32; let remoteID: UInt32 }

    private func open(_ destination: String) async throws -> Stream {
        let local = nextLocalID; nextLocalID &+= 1
        try await send(ADBMessage(command: .open, arg0: local, payload: Data(destination.utf8)))
        let response = try await receive()
        guard response.command == .okay else {
            if response.command == .clse { throw ADBError.commandFailed(String(decoding: response.payload, as: UTF8.self)) }
            throw ADBError.protocolError("expected OKAY, received \(response.command.name)")
        }
        return Stream(localID: local, remoteID: response.arg0)
    }

    private func writeSync(_ data: Data, stream: Stream) async throws {
        try await send(ADBMessage(command: .wrte, arg0: stream.localID, arg1: stream.remoteID, payload: data))
        let response = try await receive()
        guard response.command == .okay else { throw ADBError.protocolError("sync write was not acknowledged") }
    }

    private func receiveSyncResponse(stream: Stream) async throws -> (code: String, payload: Data) {
        let response = try await receive()
        guard response.command == .wrte else { throw ADBError.protocolError("sync response was not WRTE") }
        let payload = response.payload
        guard payload.count >= 8, let code = String(data: payload.prefix(4), encoding: .utf8) else { throw ADBError.invalidPacket }
        let length = readUInt32(payload, offset: 4)
        guard payload.count >= 8 + Int(length) else { throw ADBError.invalidPacket }
        try await send(ADBMessage(command: .okay, arg0: stream.localID, arg1: stream.remoteID))
        return (code, payload.subdata(in: 8..<(8 + Int(length))))
    }

    private func close(_ stream: Stream) async throws {
        try await send(ADBMessage(command: .clse, arg0: stream.localID, arg1: stream.remoteID))
    }

    private func send(_ message: ADBMessage) async throws { try await transport.send(message.encoded()) }

    private func receive() async throws -> ADBMessage {
        let header = try await readExactly(24)
        let length = readUInt32(header, offset: 12)
        guard length <= 1024 * 1024 else { throw ADBError.invalidPacket }
        return try ADBMessage.decode(header: header, payload: try await readExactly(Int(length)))
    }

    private func readExactly(_ count: Int) async throws -> Data {
        while readBuffer.count < count {
            let chunk = try await transport.receive(upTo: max(1, count - readBuffer.count))
            guard !chunk.isEmpty else { throw ADBError.connectionClosed }
            readBuffer.append(chunk)
        }
        let result = readBuffer.prefix(count); readBuffer.removeFirst(count); return Data(result)
    }

    private func littleEndian(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian, Array.init).withUnsafeBytes { Data($0) } }
    private func readUInt32(_ data: Data, offset: Int) -> UInt32 { data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian } }
}

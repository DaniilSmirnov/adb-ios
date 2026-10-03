import Foundation

/// Host-side ADB framing. A packet is a four-byte little-endian ASCII hex length
/// followed by UTF-8 payload. This is intentionally independent of a local adb server.
public enum ADBPacket {
    public static func encode(_ command: String) throws -> Data {
        guard let payload = command.data(using: .utf8), payload.count <= 0xFFFF else { throw ADBError.invalidArgument("command") }
        return Data(String(format: "%04X", payload.count).utf8) + payload
    }

    public static func decode(from data: Data) throws -> (payload: String, consumed: Int)? {
        guard data.count >= 4 else { return nil }
        guard let header = String(data: data.prefix(4), encoding: .utf8), let length = Int(header, radix: 16) else { throw ADBError.invalidPacket }
        guard data.count >= 4 + length else { return nil }
        let body = data.subdata(in: 4..<(4 + length))
        guard let payload = String(data: body, encoding: .utf8) else { throw ADBError.invalidPacket }
        return (payload, 4 + length)
    }
}

/// A message from the direct adbd transport protocol.
public struct ADBMessage: Equatable, Sendable {
    public enum Command: UInt32, Sendable {
        case sync = 0x434E5953 // SYNC
        case cnxn = 0x4E584E43 // CNXN
        case auth = 0x48545541 // AUTH
        case open = 0x4E45504F // OPEN
        case okay = 0x59414B4F // OKAY
        case clse = 0x45534C43 // CLSE
        case wrte = 0x45545257 // WRTE
    }

    public let command: Command
    public let arg0: UInt32
    public let arg1: UInt32
    public let payload: Data

    public init(command: Command, arg0: UInt32 = 0, arg1: UInt32 = 0, payload: Data = Data()) {
        self.command = command; self.arg0 = arg0; self.arg1 = arg1; self.payload = payload
    }

    public func encoded() -> Data {
        var result = Data()
        let values: [UInt32] = [command.rawValue, arg0, arg1, UInt32(payload.count), checksum(payload), command.rawValue ^ 0xFFFF_FFFF]
        for value in values { result.append(contentsOf: withUnsafeBytes(of: value.littleEndian, Array.init)) }
        result.append(payload)
        return result
    }

    public static func decode(header: Data, payload: Data) throws -> ADBMessage {
        guard header.count == 24 else { throw ADBError.invalidPacket }
        let values = stride(from: 0, to: 24, by: 4).map { index -> UInt32 in
            header.subdata(in: index..<(index + 4)).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        }
        guard let command = Command(rawValue: values[0]), values[5] == (values[0] ^ 0xFFFF_FFFF),
              values[3] == UInt32(payload.count), checksum(payload) == values[4] else { throw ADBError.invalidPacket }
        return ADBMessage(command: command, arg0: values[1], arg1: values[2], payload: payload)
    }

    private static func checksum(_ data: Data) -> UInt32 { data.reduce(UInt32(0)) { $0 &+ UInt32($1) } }
    private func checksum(_ data: Data) -> UInt32 { Self.checksum(data) }
}

public extension ADBMessage.Command {
    var name: String {
        switch self { case .sync: return "SYNC"; case .cnxn: return "CNXN"; case .auth: return "AUTH"; case .open: return "OPEN"; case .okay: return "OKAY"; case .clse: return "CLSE"; case .wrte: return "WRTE" }
    }
}

public enum ADBWireCommand {
    public static func host(_ value: String) throws -> Data { try ADBPacket.encode("host:\(value)") }
    public static func transport(_ serial: String) throws -> Data { try ADBPacket.encode("host:transport:\(serial)") }
    public static func shell(_ command: String) throws -> Data { try ADBPacket.encode("shell:\(command)") }
    public static func sync() throws -> Data { try ADBPacket.encode("sync:") }
}

import Foundation

/// Host-side ADB framing. A packet is a four-byte little-endian ASCII hex length
/// followed by UTF-8 payload. This is intentionally independent of a local adb server.
public enum ADBPacket {
    public static func encode(_ command: String) throws -> Data {
        guard let payload = command.data(using: .utf8), payload.count <= 0xFFFF_FFFF else { throw ADBError.invalidArgument("command") }
        let header = String(format: "%04X", payload.count)
        return Data(header.utf8) + payload
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

public enum ADBWireCommand {
    public static func host(_ value: String) throws -> Data { try ADBPacket.encode("host:\(value)") }
    public static func transport(_ serial: String) throws -> Data { try ADBPacket.encode("host:transport:\(serial)") }
    public static func shell(_ command: String) throws -> Data { try ADBPacket.encode("shell:\(command)") }
    public static func sync() throws -> Data { try ADBPacket.encode("sync:") }
}


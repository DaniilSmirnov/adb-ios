import Foundation

public actor ADBClient {
    private let transportFactory: @Sendable (ADBDevice) -> ADBByteTransport
    private var transport: ADBByteTransport?
    private var selectedDevice: ADBDevice?

    public init(transportFactory: @escaping @Sendable (ADBDevice) -> ADBByteTransport = { ADBNetworkTransport(host: $0.host, port: $0.port) }) {
        self.transportFactory = transportFactory
    }

    public func connect(_ device: ADBDevice) async throws {
        let connection = transportFactory(device)
        try await connection.send(try ADBWireCommand.host("device:\(device.id)"))
        try await expectOkay(connection)
        transport = connection; selectedDevice = device
    }

    public func disconnect() { transport?.close(); transport = nil; selectedDevice = nil }

    public func shell(_ command: String) async throws -> ADBCommandResult {
        guard let transport else { throw ADBError.connectionClosed }
        try await transport.send(try ADBWireCommand.shell(command))
        return try await readStream(transport)
    }

    public func install(apk: URL, replace: Bool = true, grantPermissions: Bool = false) async throws -> ADBCommandResult {
        guard FileManager.default.fileExists(atPath: apk.path) else { throw ADBError.invalidArgument("APK does not exist") }
        var flags = replace ? " -r" : ""
        if grantPermissions { flags += " -g" }
        return try await shell("pm install\(flags) /data/local/tmp/\(apk.lastPathComponent)")
    }

    public func uninstall(package: String) async throws -> ADBCommandResult { try await shell("pm uninstall \(package)") }

    private func expectOkay(_ transport: ADBByteTransport) async throws {
        let data = try await transport.receive(upTo: 4)
        guard let status = String(data: data, encoding: .utf8) else { throw ADBError.invalidPacket }
        if status == "FAIL" { throw ADBError.protocolError("remote rejected command") }
        guard status == "OKAY" else { throw ADBError.protocolError(status) }
    }

    private func readStream(_ transport: ADBByteTransport) async throws -> ADBCommandResult {
        var output = Data()
        while true {
            let chunk = try await transport.receive(upTo: 64 * 1024)
            if chunk.isEmpty { break }
            output.append(chunk)
            if chunk.count < 64 * 1024 { break }
        }
        return ADBCommandResult(output: String(data: output, encoding: .utf8) ?? String(decoding: output, as: UTF8.self))
    }
}


import Foundation

public actor ADBClient {
    private let transportFactory: @Sendable (ADBDevice) -> ADBByteTransport
    private let authenticator: ADBAuthenticator
    private var session: ADBSession?
    private var selectedDevice: ADBDevice?

    public init(transportFactory: @escaping @Sendable (ADBDevice) -> ADBByteTransport = { ADBNetworkTransport(host: $0.host, port: $0.port, tls: $0.transport == .tls) }, authenticator: ADBAuthenticator = KeychainADBAuthenticator()) {
        self.transportFactory = transportFactory; self.authenticator = authenticator
    }

    public func connect(_ device: ADBDevice) async throws {
        if selectedDevice?.id == device.id, session != nil { return }
        session?.close()
        let next = ADBSession(transport: transportFactory(device), authenticator: authenticator)
        try await next.connect()
        session = next; selectedDevice = device
    }

    public func disconnect() { session?.close(); session = nil; selectedDevice = nil }

    public func shell(_ command: String) async throws -> ADBCommandResult {
        guard let session else { throw ADBError.connectionClosed }
        return try await session.shell(command)
    }

    public func install(apk: URL, replace: Bool = true, grantPermissions: Bool = false) async throws -> ADBCommandResult {
        guard FileManager.default.fileExists(atPath: apk.path) else { throw ADBError.invalidArgument("APK does not exist") }
        guard let session else { throw ADBError.connectionClosed }
        let remote = "/data/local/tmp/DeviceManager-\(UUID().uuidString).apk"
        try await session.push(file: apk, remotePath: remote)
        var flags = replace ? " -r" : ""
        if grantPermissions { flags += " -g" }
        let result = try await session.shell("pm install\(flags) \(remote)")
        _ = try? await session.shell("rm -f \(remote)")
        return result
    }

    public func uninstall(package: String) async throws -> ADBCommandResult { try await shell("pm uninstall \(package)") }
}

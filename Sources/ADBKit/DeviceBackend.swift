import Foundation

public protocol DeviceBackend: Sendable {
    func devices() async -> [ADBDevice]
    func shell(_ command: String, on device: ADBDevice) async throws -> ADBCommandResult
    func install(_ apk: URL, on device: ADBDevice) async throws -> ADBCommandResult
    func uninstall(_ package: String, on device: ADBDevice) async throws -> ADBCommandResult
}

public actor ADBDeviceBackend: DeviceBackend {
    private let discovery: ADBDiscovery
    private var clients: [String: ADBClient]
    public init(discovery: ADBDiscovery = ADBDiscovery()) { self.discovery = discovery; clients = [:] }
    public func devices() async -> [ADBDevice] { await discovery.discover() }
    public func shell(_ command: String, on device: ADBDevice) async throws -> ADBCommandResult { let client = client(for: device); try await client.connect(device); return try await client.shell(command) }
    public func install(_ apk: URL, on device: ADBDevice) async throws -> ADBCommandResult { let client = client(for: device); try await client.connect(device); return try await client.install(apk: apk) }
    public func uninstall(_ package: String, on device: ADBDevice) async throws -> ADBCommandResult { let client = client(for: device); try await client.connect(device); return try await client.uninstall(package: package) }
    private func client(for device: ADBDevice) -> ADBClient {
        if let client = clients[device.id] { return client }
        let client = ADBClient()
        clients[device.id] = client
        return client
    }
}


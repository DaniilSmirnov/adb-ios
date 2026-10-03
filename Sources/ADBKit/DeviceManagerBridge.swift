import Foundation

public struct DeviceManagerBridgeRequest: Codable, Sendable {
    public let id: String
    public let method: String
    public let payload: Data?
    public init(id: String, method: String, payload: Data? = nil) {
        self.id = id; self.method = method; self.payload = payload
    }
}

public struct DeviceManagerBridgeResponse: Codable, Sendable {
    public let id: String
    public let ok: Bool
    public let payload: Data?
    public let error: String?
    public init(id: String, ok: Bool, payload: Data? = nil, error: String? = nil) {
        self.id = id; self.ok = ok; self.payload = payload; self.error = error
    }
}

public protocol DeviceManagerNativeBackend: Sendable {
    func listDevices() async throws -> [ADBDevice]
    func install(apk: URL, on device: ADBDevice) async throws -> ADBCommandResult
    func uninstall(package: String, on device: ADBDevice) async throws -> ADBCommandResult
    func shell(_ command: String, on device: ADBDevice) async throws -> ADBCommandResult
}

public final class ADBDeviceManagerBackendAdapter: DeviceManagerNativeBackend, @unchecked Sendable {
    private let backend: ADBDeviceBackend
    public init(backend: ADBDeviceBackend = ADBDeviceBackend()) { self.backend = backend }
    public func listDevices() async throws -> [ADBDevice] { await backend.devices() }
    public func install(apk: URL, on device: ADBDevice) async throws -> ADBCommandResult { try await backend.install(apk, on: device) }
    public func uninstall(package: String, on device: ADBDevice) async throws -> ADBCommandResult { try await backend.uninstall(package, on: device) }
    public func shell(_ command: String, on device: ADBDevice) async throws -> ADBCommandResult { try await backend.shell(command, on: device) }
}

public actor DeviceManagerBridgeRouter {
    private let backend: DeviceManagerNativeBackend
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(backend: DeviceManagerNativeBackend) { self.backend = backend }

    public func handle(_ request: DeviceManagerBridgeRequest) async -> DeviceManagerBridgeResponse {
        do {
            switch request.method {
            case "devices.list":
                return DeviceManagerBridgeResponse(id: request.id, ok: true, payload: try encoder.encode(await backend.listDevices()))
            default:
                return DeviceManagerBridgeResponse(id: request.id, ok: false, error: "Unsupported DeviceManager method")
            }
        } catch {
            return DeviceManagerBridgeResponse(id: request.id, ok: false, error: error.localizedDescription)
        }
    }

    public func decode(_ message: String) throws -> DeviceManagerBridgeRequest {
        guard let data = message.data(using: .utf8) else { throw ADBError.invalidPacket }
        return try decoder.decode(DeviceManagerBridgeRequest.self, from: data)
    }

    public func encode(_ response: DeviceManagerBridgeResponse) throws -> String {
        String(decoding: try encoder.encode(response), as: UTF8.self)
    }
}

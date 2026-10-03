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

public struct DeviceManagerDevicePayload: Codable, Sendable {
    public let device: ADBDevice
    public init(device: ADBDevice) { self.device = device }
}

public struct DeviceManagerShellPayload: Codable, Sendable {
    public let device: ADBDevice
    public let command: String
    public init(device: ADBDevice, command: String) { self.device = device; self.command = command }
}

public struct DeviceManagerInstallPayload: Codable, Sendable {
    public let device: ADBDevice
    public let fileURL: String
    public init(device: ADBDevice, fileURL: String) { self.device = device; self.fileURL = fileURL }
}

public struct DeviceManagerUninstallPayload: Codable, Sendable {
    public let device: ADBDevice
    public let packageName: String
    public init(device: ADBDevice, packageName: String) { self.device = device; self.packageName = packageName }
}

public struct DeviceManagerFilePayload: Codable, Sendable {
    public let id: String
    public let name: String
    public let size: Int64
    public let nativeToken: String
    public init(id: String, name: String, size: Int64, nativeToken: String) {
        self.id = id; self.name = name; self.size = size; self.nativeToken = nativeToken
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
            case "device.shell":
                let payload = try decode(DeviceManagerShellPayload.self, from: request.payload)
                let result = try await backend.shell(payload.command, on: payload.device)
                return DeviceManagerBridgeResponse(id: request.id, ok: true, payload: try encoder.encode(result))
            case "device.uninstall":
                let payload = try decode(DeviceManagerUninstallPayload.self, from: request.payload)
                let result = try await backend.uninstall(package: payload.packageName, on: payload.device)
                return DeviceManagerBridgeResponse(id: request.id, ok: true, payload: try encoder.encode(result))
            case "device.install":
                let payload = try decode(DeviceManagerInstallPayload.self, from: request.payload)
                let result = try await backend.install(apk: URL(fileURLWithPath: payload.fileURL), on: payload.device)
                return DeviceManagerBridgeResponse(id: request.id, ok: true, payload: try encoder.encode(result))
            default:
                return DeviceManagerBridgeResponse(id: request.id, ok: false, error: "Unsupported DeviceManager method")
            }
        } catch {
            return DeviceManagerBridgeResponse(id: request.id, ok: false, error: error.localizedDescription)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data?) throws -> T {
        guard let data else { throw ADBError.invalidArgument("bridge payload") }
        return try decoder.decode(type, from: data)
    }

    public func decode(_ message: String) throws -> DeviceManagerBridgeRequest {
        guard let data = message.data(using: .utf8) else { throw ADBError.invalidPacket }
        return try decoder.decode(DeviceManagerBridgeRequest.self, from: data)
    }

    public func encode(_ response: DeviceManagerBridgeResponse) throws -> String {
        String(decoding: try encoder.encode(response), as: UTF8.self)
    }
}

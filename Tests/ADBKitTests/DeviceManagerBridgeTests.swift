import XCTest
@testable import ADBKit

private struct FakeDeviceManagerBackend: DeviceManagerNativeBackend {
    func listDevices() async throws -> [ADBDevice] {
        [ADBDevice(id: "emulator", host: "127.0.0.1", transport: .tcp)]
    }
    func install(apk: URL, on device: ADBDevice) async throws -> ADBCommandResult { ADBCommandResult(output: "ok") }
    func uninstall(package: String, on device: ADBDevice) async throws -> ADBCommandResult { ADBCommandResult(output: "ok") }
    func shell(_ command: String, on device: ADBDevice) async throws -> ADBCommandResult { ADBCommandResult(output: command) }
}

final class DeviceManagerBridgeTests: XCTestCase {
    func testDevicesListRequest() async throws {
        let router = DeviceManagerBridgeRouter(backend: FakeDeviceManagerBackend())
        let request = DeviceManagerBridgeRequest(id: "1", method: "devices.list")
        let response = await router.handle(request)
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.id, "1")
    }

    func testUnsupportedMethodIsRejected() async {
        let router = DeviceManagerBridgeRouter(backend: FakeDeviceManagerBackend())
        let response = await router.handle(DeviceManagerBridgeRequest(id: "2", method: "unknown"))
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error, "Unsupported DeviceManager method")
    }
}

import XCTest
@testable import ADBKit

private final class FakeTransport: ADBByteTransport, @unchecked Sendable {
    var sent = [Data](); var reads: [Data]
    init(reads: [Data]) { self.reads = reads }
    func send(_ data: Data) async throws { sent.append(data) }
    func receive(upTo count: Int) async throws -> Data { reads.isEmpty ? Data() : reads.removeFirst() }
    func close() {}
}

final class ADBClientTests: XCTestCase {
    func testConnectAndShell() async throws {
        let fake = FakeTransport(reads: [
            ADBMessage(command: .cnxn, arg1: 4096, payload: Data("device::test\0".utf8)).encoded(),
            ADBMessage(command: .okay, arg0: 99, arg1: 1).encoded(),
            ADBMessage(command: .wrte, arg0: 99, arg1: 1, payload: Data("hello".utf8)).encoded(),
            ADBMessage(command: .clse, arg0: 99, arg1: 1).encoded(),
        ])
        let client = ADBClient(transportFactory: { _ in fake }, authenticator: NoopADBAuthenticator())
        let device = ADBDevice(id: "emulator", host: "127.0.0.1")
        try await client.connect(device)
        let result = try await client.shell("echo hello")
        XCTAssertEqual(result.output, "hello")
        XCTAssertEqual(fake.sent.count, 4)
    }

    func testInstallPushesApkWithSyncBeforeShellInstall() async throws {
        let syncOkay = ADBMessage(command: .okay, arg0: 1, arg1: 42).encoded()
        let fake = FakeTransport(reads: [
            ADBMessage(command: .cnxn, arg1: 4096).encoded(),
            ADBMessage(command: .okay, arg0: 42, arg1: 1).encoded(), syncOkay, syncOkay, syncOkay,
            ADBMessage(command: .wrte, arg0: 42, arg1: 1, payload: Data("OKAY".utf8) + Data([0, 0, 0, 0])).encoded(),
            ADBMessage(command: .okay, arg0: 43, arg1: 2).encoded(),
            ADBMessage(command: .clse, arg0: 43, arg1: 2).encoded(),
        ])
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("device-manager-test.apk")
        try Data([1, 2, 3, 4]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let client = ADBClient(transportFactory: { _ in fake }, authenticator: NoopADBAuthenticator())
        try await client.connect(ADBDevice(id: "device", host: "127.0.0.1"))
        let result = try await client.install(apk: file)
        XCTAssertEqual(result.output, "")
        XCTAssertTrue(fake.sent.contains { data in data.dropFirst(24).starts(with: Data("SEND".utf8)) })
        XCTAssertTrue(fake.sent.contains { data in data.dropFirst(24).starts(with: Data("DATA".utf8)) })
    }
}

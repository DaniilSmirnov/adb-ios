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
        let fake = FakeTransport(reads: [Data("OKAY".utf8), Data("hello".utf8)])
        let client = ADBClient(transportFactory: { _ in fake })
        let device = ADBDevice(id: "emulator", host: "127.0.0.1")
        try await client.connect(device)
        let result = try await client.shell("echo hello")
        XCTAssertEqual(result.output, "hello")
        XCTAssertEqual(fake.sent.count, 2)
    }
}


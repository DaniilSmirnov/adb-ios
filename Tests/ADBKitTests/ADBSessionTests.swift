import XCTest
@testable import ADBKit

private final class SessionTransport: ADBByteTransport, @unchecked Sendable {
    var sent: [Data] = []
    var reads: [Data]
    init(reads: [Data]) { self.reads = reads }
    func send(_ data: Data) async throws { sent.append(data) }
    func receive(upTo count: Int) async throws -> Data { reads.isEmpty ? Data() : reads.removeFirst() }
    func close() {}
}

private struct TestAuthenticator: ADBAuthenticator {
    func signature(for token: Data) async throws -> Data? { Data("signature:\(token.count)".utf8) }
    func publicKey() async throws -> Data? { nil }
}

final class ADBSessionTests: XCTestCase {
    func testAuthTokenIsSignedBeforeCnxn() async throws {
        let transport = SessionTransport(reads: [
            ADBMessage(command: .auth, arg0: 1, payload: Data(repeating: 7, count: 16)).encoded(),
            ADBMessage(command: .cnxn, arg1: 4096).encoded(),
        ])
        let session = ADBSession(transport: transport, authenticator: TestAuthenticator())
        try await session.connect()
        let auth = try ADBMessage.decode(header: Data(transport.sent[1].prefix(24)), payload: Data(transport.sent[1].dropFirst(24)))
        XCTAssertEqual(auth.command, .auth)
        XCTAssertEqual(auth.arg0, 2)
        XCTAssertEqual(auth.payload, Data("signature:16".utf8))
    }

    func testAuthWithoutProviderFailsClosed() async {
        let transport = SessionTransport(reads: [ADBMessage(command: .auth, arg0: 1, payload: Data([1])).encoded()])
        let session = ADBSession(transport: transport, authenticator: NoopADBAuthenticator())
        do {
            try await session.connect()
            XCTFail("expected authenticationRequired")
        } catch let error as ADBError {
            if case .authenticationRequired = error { } else { XCTFail("unexpected ADB error: \(error)") }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}

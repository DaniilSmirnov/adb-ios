import XCTest
@testable import ADBKit

final class ADBPacketTests: XCTestCase {
    func testRoundTripAndPartialFrames() throws {
        let encoded = try ADBPacket.encode("shell:echo Привет")
        XCTAssertNil(try ADBPacket.decode(from: Data(encoded.prefix(3))))
        let decoded = try XCTUnwrap(try ADBPacket.decode(from: encoded))
        XCTAssertEqual(decoded.payload, "shell:echo Привет")
        XCTAssertEqual(decoded.consumed, encoded.count)
    }

    func testInvalidHeader() { XCTAssertThrowsError(try ADBPacket.decode(from: Data("zzzz".utf8))) }

    func testDirectAdbMessageRoundTrip() throws {
        let message = ADBMessage(command: .wrte, arg0: 7, arg1: 9, payload: Data("payload".utf8))
        let encoded = message.encoded()
        let decoded = try ADBMessage.decode(header: Data(encoded.prefix(24)), payload: Data(encoded.dropFirst(24)))
        XCTAssertEqual(decoded, message)
    }

    func testDirectAdbMessageRejectsCorruptChecksum() {
        var encoded = ADBMessage(command: .okay, arg0: 1, arg1: 2).encoded()
        encoded[16] = 0xff
        XCTAssertThrowsError(try ADBMessage.decode(header: Data(encoded.prefix(24)), payload: Data(encoded.dropFirst(24))))
    }
}

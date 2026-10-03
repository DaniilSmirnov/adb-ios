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
}


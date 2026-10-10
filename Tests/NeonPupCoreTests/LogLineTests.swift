import XCTest
@testable import NeonPupCore

final class LogLineTests: XCTestCase {
    func testPicksLastErrorAndStripsColor() {
        let text = "\u{1B}[36mINFO\u{1B}[0m started\n\u{1B}[31mERROR\u{1B}[0m [1 2ms] dial us-reality: EOF\nINFO ok\n\u{1B}[31mFATAL\u{1B}[0m start service: tun: permission denied\n"
        XCTAssertEqual(LogLine.lastError(in: text), "FATAL start service: tun: permission denied")
    }

    func testNoErrorGivesNil() {
        XCTAssertNil(LogLine.lastError(in: "INFO all good\nWARN slow\n"))
    }
}

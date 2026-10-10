import XCTest
@testable import NeonPupCore

final class TimeZonePolicyTests: XCTestCase {
    func testChinaZonesBecomeSingapore() {
        for zone in ["Asia/Shanghai", "Asia/Hong_Kong", "Asia/Macau", "Asia/Chongqing", "Asia/Harbin", "PRC"] {
            XCTAssertEqual(TimeZonePolicy.replacement(for: zone), "Asia/Singapore", zone)
        }
    }

    func testOtherZonesUntouched() {
        for zone in ["Asia/Makassar", "Asia/Ho_Chi_Minh", "Asia/Singapore", "Europe/Berlin", "Asia/Urumqi", ""] {
            XCTAssertNil(TimeZonePolicy.replacement(for: zone), zone)
        }
    }
}

import XCTest
@testable import NeonPupCore

/// Own roads: the list is the person's roads, in their order, named by them.
final class RoadsTests: XCTestCase {
    func testRoadsFollowTheUsersList() {
        let roads = Roads.from([RoadValidatorTests.reality, RoadValidatorTests.hy2])
        XCTAssertEqual(roads.map(\.tag), ["road-1", "road-2"])
        XCTAssertEqual(roads.map(\.name), ["Singapore everyday", "Singapore turbo"])
        XCTAssertEqual(Roads.from([]), [])
    }

    func testHeartBoundaries() {
        XCTAssertEqual(Hearts.count(delayMs: nil), 0)
        XCTAssertEqual(Hearts.count(delayMs: 0), 0)
        XCTAssertEqual(Hearts.count(delayMs: 1), 3)
        XCTAssertEqual(Hearts.count(delayMs: 149), 3)
        XCTAssertEqual(Hearts.count(delayMs: 150), 2)
        XCTAssertEqual(Hearts.count(delayMs: 399), 2)
        XCTAssertEqual(Hearts.count(delayMs: 400), 1)
    }
}

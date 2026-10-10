import XCTest
@testable import NeonPupCore

/// Secure / Fast / Manual (the maintainer 2026-10-10): Claude always takes the first working road in the fixed
/// order (Singapore first, US only when both Singapore roads are dead), never "whichever is faster".
final class RoadPolicyTests: XCTestCase {
    let order = ["sg-reality", "sg-hysteria2", "us-reality", "us-hysteria2", "cloudflare-ws"]
    var all: Set<String> { Set(order) }

    func testSecureUsesFixedOrderForEverything() {
        XCTAssertEqual(RoadPolicy.selection(mode: .secure, picked: nil, alive: all, order: order),
                       RoadSelection(choice: "sg-reality", claude: "sg-reality", pickedRoadDown: false))
        XCTAssertEqual(RoadPolicy.selection(mode: .secure, picked: nil, alive: all.subtracting(["sg-reality"]), order: order),
                       RoadSelection(choice: "sg-hysteria2", claude: "sg-hysteria2", pickedRoadDown: false))
        XCTAssertEqual(RoadPolicy.selection(mode: .secure, picked: nil, alive: ["us-reality", "cloudflare-ws"], order: order),
                       RoadSelection(choice: "us-reality", claude: "us-reality", pickedRoadDown: false))
    }

    func testFastLetsEverythingElseRaceButClaudeStaysOrdered() {
        XCTAssertEqual(RoadPolicy.selection(mode: .fast, picked: nil, alive: all, order: order),
                       RoadSelection(choice: "auto", claude: "sg-reality", pickedRoadDown: false))
    }

    func testManualUsesThePickAndFallsBackInOrder() {
        XCTAssertEqual(RoadPolicy.selection(mode: .manual, picked: "us-hysteria2", alive: all, order: order),
                       RoadSelection(choice: "us-hysteria2", claude: "sg-reality", pickedRoadDown: false))
        XCTAssertEqual(RoadPolicy.selection(mode: .manual, picked: "us-hysteria2", alive: ["sg-hysteria2", "cloudflare-ws"], order: order),
                       RoadSelection(choice: "sg-hysteria2", claude: "sg-hysteria2", pickedRoadDown: true))
        XCTAssertEqual(RoadPolicy.selection(mode: .manual, picked: nil, alive: all, order: order),
                       RoadSelection(choice: "sg-reality", claude: "sg-reality", pickedRoadDown: false))
    }

    func testNothingAliveMeansNoSelection() {
        for mode in [RoadMode.secure, .fast, .manual] {
            XCTAssertNil(RoadPolicy.selection(mode: mode, picked: "sg-reality", alive: [], order: order))
        }
    }

    func testStoredModesMigrate() {
        XCTAssertEqual(RoadMode(stored: "auto"), .secure)   // old "Auto" becomes the safest mode
        XCTAssertEqual(RoadMode(stored: "manual"), .manual)
        XCTAssertEqual(RoadMode(stored: "fast"), .fast)
        XCTAssertEqual(RoadMode(stored: nil), .secure)
        XCTAssertEqual(RoadMode(stored: "garbage"), .secure)
    }
}

import XCTest
import NeonPupCore

/// the maintainer 2026-10-10: the hotel button only where a login page cannot appear by itself.
final class HotelLinkTests: XCTestCase {
    func show(_ p: Phase, _ china: Bool) -> Bool { AppStateMachine.showsHotelLogin(p, chinaMode: china) }

    func testHiddenWhenNothingBlocksTheMacsOwnPopUp() {
        XCTAssertFalse(show(.off, false))
        XCTAssertFalse(show(.connected, false))
        XCTAssertFalse(show(.connected, true))
        XCTAssertFalse(show(.connecting, true))
        XCTAssertFalse(show(.hotelLogin, true))
        XCTAssertFalse(show(.trouble(.roadClosed), true))
        XCTAssertFalse(show(.trouble(.noRoads), true))
        XCTAssertFalse(show(.trouble(.needsApproval), true))
        XCTAssertFalse(show(.trouble(.otherVPN), true))
        XCTAssertFalse(show(.trouble(.notSealed), true))
    }

    func testShownWhenTheLoginPageCannotAppear() {
        XCTAssertTrue(show(.off, true))
        XCTAssertTrue(show(.failed, false))
        XCTAssertTrue(show(.trouble(.allRoadsSleepy), false))
        XCTAssertTrue(show(.trouble(.noInternet), false))
    }
}

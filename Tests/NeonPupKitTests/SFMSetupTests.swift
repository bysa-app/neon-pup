import XCTest
@testable import NeonPupKit

/// The wizard always shows the first step that isn't done yet, so it resumes correctly after a restart.
final class SFMSetupTests: XCTestCase {
    func step(_ done: Int) -> SFMSetup.Step {
        let flags = (0..<9).map { $0 < done }
        return SFMSetup.firstUnmet(welcomed: flags[0], helperReady: flags[1], installed: flags[2], extensionEnabled: flags[3],
                                   hasRoads: flags[4], fetched: flags[5], vpnAdded: flags[6], settingConfirmed: flags[7],
                                   firstStart: flags[8])
    }

    func testStepsComeInOrder() {
        XCTAssertEqual((0...9).map(step), [.welcome, .helper, .install, .systemExtension, .servers, .sendToSFM,
                                           .addVPN, .sfmSetting, .firstStart, .done])
    }

    func testALaterStepNeverHidesAnEarlierMissingOne() {
        // SFM removed after setup: everything else still recorded, so it must go back to installing.
        XCTAssertEqual(SFMSetup.firstUnmet(welcomed: true, helperReady: true, installed: false, extensionEnabled: true,
                                           hasRoads: true, fetched: true, vpnAdded: true, settingConfirmed: true,
                                           firstStart: true), .install)
    }
}

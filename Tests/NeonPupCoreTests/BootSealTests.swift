import XCTest
import NeonPupCore

/// Codex review 2026-10-10 (bricking #1): power loss or a crash while connected outside China mode left the
/// "wanted" flag on disk, so the helper (RunAtLoad) sealed the Mac at the next boot with no app running to
/// lift it. Only China mode may keep the block across a restart; a helper crash within the same boot keeps it.
final class BootSealTests: XCTestCase {
    func keep(_ wanted: Bool, china: Bool, recorded: String?, now: String = "1760000000") -> Bool {
        KillSwitchBootPolicy.keepAtLaunch(wanted: wanted, chinaMode: china, recordedBoot: recorded, currentBoot: now)
    }

    func testEarlierBootWithoutChinaModeIsDropped() {
        XCTAssertFalse(keep(true, china: false, recorded: "1759990000"))
    }

    func testChinaModeSurvivesARestart() {
        XCTAssertTrue(keep(true, china: true, recorded: "1759990000"))
    }

    func testHelperCrashInTheSameBootKeepsTheBlock() {
        XCTAssertTrue(keep(true, china: false, recorded: "1760000000"))
    }

    func testFlagFromAnOlderVersionWithoutBootRecordIsDropped() {
        // Versions before this fix wrote an empty file: treat it as an earlier boot.
        XCTAssertFalse(keep(true, china: false, recorded: nil))
        XCTAssertFalse(keep(true, china: false, recorded: ""))
    }

    func testNothingWantedStaysUnsealed() {
        XCTAssertFalse(keep(false, china: true, recorded: "1760000000"))
    }

    func testBootIDIsStableAndNumeric() {
        let a = KillSwitchBootPolicy.currentBoot(), b = KillSwitchBootPolicy.currentBoot()
        XCTAssertNotNil(a)
        XCTAssertEqual(a, b)
        XCTAssertNotNil(Int(a ?? ""), "seconds since 1970")
    }

    /// Codex boot review #6: an unknown boot (lookup failed) never counts as "the same boot".
    func testUnknownBootIsNeverTheSameBoot() {
        XCTAssertFalse(KillSwitchBootPolicy.keepAtLaunch(wanted: true, chinaMode: false, recordedBoot: "unknown", currentBoot: nil))
        XCTAssertFalse(KillSwitchBootPolicy.keepAtLaunch(wanted: true, chinaMode: false, recordedBoot: "1760000000", currentBoot: nil))
        XCTAssertFalse(KillSwitchBootPolicy.keepAtLaunch(wanted: true, chinaMode: false, recordedBoot: "unknown", currentBoot: "unknown"))
        XCTAssertTrue(KillSwitchBootPolicy.keepAtLaunch(wanted: true, chinaMode: true, recordedBoot: nil, currentBoot: nil))
    }
}

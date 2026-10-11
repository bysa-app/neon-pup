import XCTest
@testable import NeonPupKit
import NeonPupCore

/// Codex review of the current app, 2026-10-10: each test reproduces one finding.
@MainActor
final class AppReviewRound2Tests: XCTestCase {
    private func model(_ h: FakeHelper, _ e: FakeEngine, defaults: UserDefaults? = nil) -> AppModel {
        AppModel(helper: h, makeEngine: { _, _ in e }, probe: FakeProbe(works: true),
                 defaults: defaults ?? UserDefaults(suiteName: "r2-\(UUID().uuidString)")!,
                 store: InMemoryRoadStore(TestRoads.five), pause: { _ in }, monitorEnabled: false,
                 otherVPN: { nil }, openLoginPage: {})
    }

    /// #1: a seal that failed before connecting must not be shown as "I paused the internet".
    func testFailedFirstSealIsNotShownAsPaused() async {
        let h = FakeHelper(), e = FakeEngine(); h.killSwitchError = "pf refused the rules"
        let m = model(h, e)
        await m.wake()
        XCTAssertEqual(m.phase, .trouble(.notSealed))
        XCTAssertEqual(h.startCount, 0)
    }

    /// #1: once the retry works while the engine still runs, she is connected again, not "paused".
    func testSealRecoveryWithRunningEngineReconnects() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let m = model(h, e)
        await m.wake()
        h.killSwitchError = "pf refused the rules"
        await m.check()
        XCTAssertEqual(m.phase, .trouble(.notSealed))
        h.killSwitchError = nil
        await m.networkChanged()
        XCTAssertEqual(m.phase, .connected)
    }

    /// #2: an app restart during the hotel window must close it (the engine keeps running in Direct).
    func testReattachClosesHotelWindow() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let d = UserDefaults(suiteName: "r2-\(UUID().uuidString)")!
        let m = model(h, e, defaults: d)
        await m.wake()
        await m.startHotelLogin()
        XCTAssertEqual(e.modes.last, "Direct")
        let fresh = model(h, e, defaults: d)
        await fresh.reattach()
        XCTAssertEqual(e.modes.last, "Rule")
    }

    /// #2: if the window cannot be closed on the running engine, restart it (a new engine starts in Rule).
    func testReattachRestartsWhenHotelWindowWontClose() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let d = UserDefaults(suiteName: "r2-\(UUID().uuidString)")!
        let m = model(h, e, defaults: d)
        await m.wake()
        await m.startHotelLogin()
        e.refusedModes = ["Rule"]
        let fresh = model(h, e, defaults: d)
        await fresh.reattach()
        XCTAssertEqual(h.startCount, 2)
    }

    /// #3: a refused close of the hotel window restarts the engine instead of staying direct.
    func testRefusedHotelCloseRestartsEngine() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let m = model(h, e)
        await m.wake()
        await m.startHotelLogin()
        e.refusedModes = ["Rule"]
        // A restarted engine starts in Rule; the fake keeps one object, so report what the new engine would.
        e.reportedMode = "Rule"
        await m.endHotelLogin()
        XCTAssertEqual(h.startCount, 2)
        XCTAssertEqual(m.phase, .connected)
    }

    /// #6: a nap while a reconnect is stopping the engine wins; nothing starts again.
    func testNapDuringReconnectStays() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let m = model(h, e)
        await m.wake()
        h.duringStop = { await m.nap() }
        await m.setRoads([TestRoads.five[0]])
        XCTAssertEqual(m.phase, .off)
        XCTAssertFalse(h.running)
        XCTAssertEqual(h.startCount, 1)
    }

    /// #8: deleting every road while connected puts the time zone back.
    func testDeletingAllRoadsRestoresTimeZone() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let m = model(h, e)
        await m.wake()
        await m.setRoads([])
        XCTAssertEqual(m.phase, .trouble(.noRoads))
        XCTAssertEqual(h.calls.filter { $0.contains("TimeZone") }.last, "restoreTimeZone")
    }
}

@MainActor
final class QuitCleanupTests: XCTestCase {
    /// #7: quitting from "paused" outside China mode must lift the kill switch.
    func testPausedNeedsStopOnQuit() async {
        let h = FakeHelper(), e = FakeEngine(); h.startError = "engine died"
        let m = AppModel(helper: h, makeEngine: { _, _ in e }, probe: FakeProbe(works: true),
                         defaults: UserDefaults(suiteName: "r2-\(UUID().uuidString)")!,
                         store: InMemoryRoadStore(TestRoads.five), pause: { _ in }, monitorEnabled: false,
                         otherVPN: { nil }, openLoginPage: {})
        await m.wake()
        XCTAssertEqual(m.phase, .failed)
        XCTAssertTrue(m.needsStopOnQuit)
        m.stopForQuit()
        XCTAssertEqual(h.calls.last, "killSwitch(off)")
    }
}

/// Fable review of the current app, 2026-10-10.
@MainActor
final class FableRound2Tests: XCTestCase {
    private func model(_ h: FakeHelper, _ e: FakeEngine) -> AppModel {
        AppModel(helper: h, makeEngine: { _, _ in e }, probe: FakeProbe(works: true),
                 defaults: UserDefaults(suiteName: "f2-\(UUID().uuidString)")!,
                 store: InMemoryRoadStore(TestRoads.five), pause: { _ in }, monitorEnabled: false,
                 otherVPN: { nil }, openLoginPage: {})
    }

    /// #1: a second Save while the first reconnect is stopping the engine: the last save wins, and the app
    /// ends connected with the engine running (never "off" with the engine still up).
    func testDoubleSaveEndsConnectedOnLastRoads() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let m = model(h, e)
        await m.wake()
        h.duringStop = { await m.setRoads([TestRoads.five[1]]) }
        await m.setRoads([TestRoads.five[0]])
        XCTAssertEqual(m.phase, .connected)
        XCTAssertTrue(h.running)
        XCTAssertEqual(h.startedRoads.last, [TestRoads.five[1]])
        XCTAssertNotEqual(h.calls.last, "killSwitch(off)")
    }

    /// #3: renaming the picked road keeps the pick.
    func testRenamingPickedRoadKeepsPick() async {
        let h = FakeHelper(), e = FakeEngine()
        let m = model(h, e)
        await m.pick("road-2")
        var specs = TestRoads.five
        specs[1].name = "Fast one"
        await m.setRoads(specs)
        XCTAssertEqual(m.pickedRoad, "road-2")
    }

    /// #4: a typed name is kept as typed (no percent-decoding), trimmed, never empty.
    func testTypedNamesAreNotDecoded() {
        XCTAssertEqual(ShareLinkParser.finishTypedName("Road %2520"), "Road %2520")
        XCTAssertEqual(ShareLinkParser.finishTypedName("100%41"), "100%41")
        XCTAssertEqual(ShareLinkParser.finishTypedName("  Home  "), "Home")
        XCTAssertEqual(ShareLinkParser.finishTypedName("   "), "Server")
    }

    /// #5: "Line N" is the line the person sees, blank lines included.
    func testLineNumbersCountBlankLines() {
        let items = ShareLinkParser.parseAll("\n\nnot-a-link\n\nalso-bad")
        XCTAssertEqual(items.map(\.number), [3, 5])
    }
}

/// the maintainer 2026-10-10: the direct window closes as soon as a server answers again (he is logged in), so the
/// browser does not keep using the local connection for the rest of the 5 minutes.
@MainActor
final class HotelAutoCloseTests: XCTestCase {
    func testWindowClosesOnceAServerAnswers() async {
        let h = FakeHelper(), e = FakeEngine()
        let m = AppModel(helper: h, makeEngine: { _, _ in e }, probe: FakeProbe(works: true),
                         defaults: UserDefaults(suiteName: "hc-\(UUID().uuidString)")!,
                         store: InMemoryRoadStore(TestRoads.five), pause: { _ in }, monitorEnabled: false,
                         otherVPN: { nil }, openLoginPage: {})
        await m.wake()                       // behind a login page: no server answers
        XCTAssertEqual(m.phase, .trouble(.allRoadsSleepy))
        await m.startHotelLogin()
        XCTAssertEqual(m.phase, .hotelLogin)
        await m.hotelLoginTick()             // still not logged in: stays open
        XCTAssertEqual(m.phase, .hotelLogin)
        e.delays = ["road-1": 80]            // logged in: the first server answers
        await m.hotelLoginTick()
        XCTAssertEqual(e.modes.last, "Rule")
        XCTAssertEqual(m.phase, .connected)
    }
}

/// Codex review 2026-10-10 (bricking #1): the helper must know China mode, because only then does a block
/// survive a restart.
@MainActor
final class ChinaModeReachesHelperTests: XCTestCase {
    func testChinaModeIsSentBeforeEveryKillSwitchChange() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let m = AppModel(helper: h, makeEngine: { _, _ in e }, probe: FakeProbe(works: true),
                         defaults: UserDefaults(suiteName: "cm-\(UUID().uuidString)")!,
                         store: InMemoryRoadStore(TestRoads.five), pause: { _ in }, monitorEnabled: false,
                         otherVPN: { nil }, openLoginPage: {})
        await m.setChinaMode(true)
        XCTAssertEqual(h.chinaModeSent.last, true)
        await m.wake()
        XCTAssertEqual(h.chinaModeSent.last, true)
        await m.setChinaMode(false)
        XCTAssertEqual(h.chinaModeSent.last, false)
    }

    /// Codex boot review #1: China mode changes only once the helper has it; otherwise the helper's flag
    /// and the app disagree and a restart can seal a Mac whose owner turned China mode off.
    func testChinaModeChangesOnlyWhenTheHelperConfirms() async {
        let h = FakeHelper(), e = FakeEngine()
        let m = AppModel(helper: h, makeEngine: { _, _ in e }, probe: FakeProbe(works: true),
                         defaults: UserDefaults(suiteName: "cm-\(UUID().uuidString)")!,
                         store: InMemoryRoadStore(TestRoads.five), pause: { _ in }, monitorEnabled: false,
                         otherVPN: { nil }, openLoginPage: {})
        await m.setChinaMode(true)
        h.chinaModeError = "could not reach the helper"
        await m.setChinaMode(false)
        XCTAssertTrue(m.chinaMode, "still on: the helper never heard it was turned off")
        XCTAssertEqual(m.lastError, "could not reach the helper")
    }

    /// Codex boot review #4: a nap while wake waits for the China-mode reply wins; wake must not seal after it.
    func testNapDuringChinaModeSyncIsNotResealed() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let m = AppModel(helper: h, makeEngine: { _, _ in e }, probe: FakeProbe(works: true),
                         defaults: UserDefaults(suiteName: "cm-\(UUID().uuidString)")!,
                         store: InMemoryRoadStore(TestRoads.five), pause: { _ in }, monitorEnabled: false,
                         otherVPN: { nil }, openLoginPage: {})
        h.duringChinaMode = { await m.nap() }
        await m.wake()
        XCTAssertEqual(m.phase, .off)
        XCTAssertEqual(h.calls.filter { $0.hasPrefix("killSwitch") }.last, "killSwitch(off)")
        XCTAssertEqual(h.startCount, 0)
    }
}

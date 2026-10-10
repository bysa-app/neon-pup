import XCTest
@testable import NeonPupKit
@testable import NeonPupCore

/// Extension 2026-10-10: Secure/Fast/Manual, kill switch, China mode, hotel login, other VPN app.
@MainActor
final class AppModelExtensionTests: XCTestCase {
    var helper: FakeHelper!
    var engine: FakeEngine!
    var otherVPN: String?
    let allRoads = Dictionary(uniqueKeysWithValues: Roads.from(TestRoads.five).map { ($0.tag, 60) })

    func make() -> AppModel {
        helper = FakeHelper()
        engine = FakeEngine()
        let eng = engine!
        return AppModel(helper: helper, makeEngine: { _, _ in eng }, probe: FakeProbe(works: true),
                        defaults: UserDefaults(suiteName: "np-ext-\(UUID().uuidString)")!,
                        store: InMemoryRoadStore(TestRoads.five), pause: { _ in }, monitorEnabled: false,
                        otherVPN: { [unowned self] in self.otherVPN }, openLoginPage: {})
    }

    func testSecureIsTheDefaultAndPinsBothToSingapore() async {
        let m = make()
        XCTAssertEqual(m.mode, .secure)
        engine.delays = allRoads
        await m.wake()
        XCTAssertEqual(m.phase, .connected)
        XCTAssertEqual(engine.selected.last, "road-1")
        XCTAssertEqual(engine.claudeSelected.last, "road-1")
    }

    func testClaudeFailsOverInOrderNotBySpeed() async {
        let m = make()
        var delays = allRoads
        delays["road-1"] = nil
        delays["road-3"] = 20          // faster, but America comes after Singapore
        engine.delays = delays
        await m.wake()
        XCTAssertEqual(engine.claudeSelected.last, "road-2")
    }

    func testFastRacesEverythingElseButNotClaude() async {
        let m = make()
        await m.setMode(.fast)
        engine.delays = allRoads
        await m.wake()
        XCTAssertEqual(engine.selected.last, "auto")
        XCTAssertEqual(engine.claudeSelected.last, "road-1")
    }

    func testKillSwitchGoesOnBeforeTheEngineAndOffAfterNap() async {
        let m = make()
        engine.delays = allRoads
        await m.wake()
        XCTAssertEqual(Array(helper.calls.prefix(2)), ["killSwitch(on)", "start"])
        await m.nap()
        XCTAssertTrue(helper.calls.suffix(3).contains("killSwitch(off)"))
    }

    func testEngineDeathKeepsEverythingBlocked() async {
        let m = make()
        engine.delays = allRoads
        await m.wake()
        helper.running = false
        await m.check()
        XCTAssertEqual(m.phase, .failed)
        XCTAssertFalse(helper.calls.contains("killSwitch(off)"), "a dead tunnel must not open the direct way out")
    }

    func testChinaModeBlocksEvenWhileNapping() async {
        let m = make()
        await m.setChinaMode(true)
        XCTAssertEqual(helper.calls, ["killSwitch(on)"])
        engine.delays = allRoads
        await m.wake()
        await m.nap()
        XCTAssertFalse(helper.calls.contains("killSwitch(off)"))
        await m.setChinaMode(false)
        XCTAssertEqual(helper.calls.last, "killSwitch(off)")
    }

    func testChinaModeOffWhileConnectedKeepsTheKillSwitch() async {
        let m = make()
        await m.setChinaMode(true)
        engine.delays = allRoads
        await m.wake()
        await m.setChinaMode(false)
        XCTAssertNotEqual(helper.calls.last, "killSwitch(off)", "still connected: the kill switch stays")
    }

    func testQuitKeepsTheKillSwitchOnlyInChinaMode() async {
        let m = make()
        engine.delays = allRoads
        await m.wake()
        m.stopForQuit()
        XCTAssertEqual(Array(helper.calls.suffix(2)), ["stopNow", "killSwitch(off)"])
        let n = make()
        await n.setChinaMode(true)
        engine.delays = allRoads
        await n.wake()
        n.stopForQuit()
        XCTAssertEqual(helper.calls.last, "stopNow")
    }

    func testAnotherVPNAppBlocksWaking() async {
        let m = make()
        otherVPN = "Clash"
        await m.wake()
        XCTAssertEqual(m.phase, .trouble(.otherVPN))
        XCTAssertTrue(helper.calls.isEmpty, "nothing may start or change: \(helper.calls)")
    }

    func testHotelLoginOpensEverythingElseButKeepsClaudeOnTheRoad() async {
        let m = make()
        engine.delays = allRoads
        await m.wake()
        await m.startHotelLogin()
        XCTAssertEqual(m.phase, .hotelLogin)
        XCTAssertEqual(engine.modes.last, "Direct")
        XCTAssertEqual(engine.claudeSelected.last, "road-1")
        XCTAssertFalse(engine.claudeSelected.contains("direct"))
        XCTAssertFalse(engine.selected.contains("direct"))
        await m.check()
        XCTAssertEqual(engine.modes.last, "Direct", "checks must not close the login window")
        await m.endHotelLogin()
        XCTAssertEqual(m.phase, .connected)
        XCTAssertEqual(engine.modes.last, "Rule")
    }

    func testHotelLoginFromNappingWakesFirst() async {
        let m = make()
        engine.delays = allRoads
        await m.startHotelLogin()
        XCTAssertEqual(helper.calls.filter { $0 == "start" }.count, 1)
        XCTAssertEqual(m.phase, .hotelLogin)
        XCTAssertEqual(engine.modes.last, "Direct")
    }

    func testReattachInChinaModeRestoresTheKillSwitch() async {
        let defaults = UserDefaults(suiteName: "np-reattach-\(UUID().uuidString)")!
        defaults.set(true, forKey: "chinaMode")
        helper = FakeHelper()
        let m = AppModel(helper: helper, makeEngine: { _, _ in FakeEngine() }, probe: FakeProbe(works: true),
                         defaults: defaults, store: InMemoryRoadStore(TestRoads.five), pause: { _ in }, monitorEnabled: false, otherVPN: { nil }, openLoginPage: {})
        await m.reattach()
        XCTAssertTrue(helper.calls.contains("killSwitch(on)"))
        XCTAssertTrue(m.chinaMode)
    }
}

/// Security review 2026-10-10: while connected, every check re-confirms the tunnel with the helper,
/// which seals the Mac if the tunnel no longer carries the route.
@MainActor
final class AppModelTunnelGuardTests: XCTestCase {
    func testEveryCheckReconfirmsTheKillSwitch() async {
        let helper = FakeHelper(), engine = FakeEngine()
        engine.delays = Dictionary(uniqueKeysWithValues: Roads.from(TestRoads.five).map { ($0.tag, 60) })
        let m = AppModel(helper: helper, makeEngine: { _, _ in engine }, probe: FakeProbe(works: true),
                         defaults: UserDefaults(suiteName: "np-guard-\(UUID().uuidString)")!,
                         store: InMemoryRoadStore(TestRoads.five), pause: { _ in }, monitorEnabled: false,
                         otherVPN: { nil }, openLoginPage: {})
        await m.wake()
        let before = helper.calls.filter { $0 == "killSwitch(on)" }.count
        await m.check()
        XCTAssertEqual(helper.calls.filter { $0 == "killSwitch(on)" }.count, before + 1)
    }
}

/// Final review #3/#9/#11: hotel window always closes; nap order; nap during the kill switch call.
@MainActor
final class AppModelReviewFixTests: XCTestCase {
    var helper: FakeHelper!
    var engine: FakeEngine!
    func make() -> AppModel {
        helper = FakeHelper(); engine = FakeEngine()
        let eng = engine!
        return AppModel(helper: helper, makeEngine: { _, _ in eng }, probe: FakeProbe(works: true),
                        defaults: UserDefaults(suiteName: "np-fix-\(UUID().uuidString)")!,
                        store: InMemoryRoadStore(TestRoads.five), pause: { _ in }, monitorEnabled: false,
                        otherVPN: { nil }, openLoginPage: {})
    }

    func testHotelWindowClosesEvenWhenNoRoadAnswers() async {
        let m = make()
        engine.delays = Dictionary(uniqueKeysWithValues: Roads.from(TestRoads.five).map { ($0.tag, 60) })
        await m.startHotelLogin()
        engine.delays = [:]
        await m.endHotelLogin()
        XCTAssertEqual(engine.modes.last, "Rule", "the direct window must close whatever the roads do")
    }

    func testNapLiftsTheKillSwitchBeforeStoppingOutsideChinaMode() async {
        let m = make()
        engine.delays = ["road-1": 60]
        await m.wake()
        await m.nap()
        let off = helper.calls.lastIndex(of: "killSwitch(off)")!
        let stop = helper.calls.lastIndex(of: "stop")!
        XCTAssertLessThan(off, stop, "otherwise every nap seals and drops all open connections for nothing")
    }

    func testNapDuringTheKillSwitchCallDoesNotStartTheEngine() async {
        let m = make()
        helper.duringKillSwitch = { await m.nap() }
        await m.wake()
        XCTAssertFalse(helper.calls.contains("start"), "\(helper.calls)")
        XCTAssertEqual(m.phase, .off)
    }

    func testChinaModeAfterAnOSUpdateAsksForApprovalInsteadOfPretending() async {
        let defaults = UserDefaults(suiteName: "np-fix-ok-\(UUID().uuidString)")!
        defaults.set(true, forKey: "chinaMode")
        helper = FakeHelper()
        helper.ready = .needsApproval
        let m = AppModel(helper: helper, makeEngine: { _, _ in FakeEngine() }, probe: FakeProbe(works: true),
                         defaults: defaults, store: InMemoryRoadStore(TestRoads.five), pause: { _ in }, monitorEnabled: false,
                         otherVPN: { nil }, openLoginPage: {})
        await m.reattach()
        XCTAssertEqual(m.phase, .trouble(.needsApproval))
    }
}

/// Security review 2026-10-10: when a needed seal fails the panel must never claim the Mac is blocked.
@MainActor
final class AppModelSealFailureTests: XCTestCase {
    func make(_ helper: FakeHelper, _ engine: FakeEngine) -> AppModel {
        AppModel(helper: helper, makeEngine: { _, _ in engine }, probe: FakeProbe(works: true),
                 defaults: UserDefaults(suiteName: "np-seal-\(UUID().uuidString)")!,
                 store: InMemoryRoadStore(TestRoads.five), pause: { _ in }, monitorEnabled: false,
                 otherVPN: { nil }, openLoginPage: {})
    }

    func testChinaModeThatCannotSealSaysSo() async {
        let helper = FakeHelper()
        helper.killSwitchError = "pf refused the rules"
        let m = make(helper, FakeEngine())
        await m.setChinaMode(true)
        XCTAssertEqual(m.phase, .trouble(.notSealed))
        XCTAssertEqual(m.lastError, "pf refused the rules")
    }

    func testNapInChinaModeThatCannotSealSaysSo() async {
        let helper = FakeHelper(), engine = FakeEngine()
        engine.delays = ["road-1": 60]
        let m = make(helper, engine)
        await m.setChinaMode(true)
        await m.wake()
        helper.killSwitchError = "pf could not be enabled"
        await m.nap()
        XCTAssertEqual(m.phase, .trouble(.notSealed))
    }

    func testEngineDeathWithAFailedSealIsNotCalledPaused() async {
        let helper = FakeHelper(), engine = FakeEngine()
        engine.delays = ["road-1": 60]
        let m = make(helper, engine)
        await m.wake()
        helper.running = false
        helper.lastError = "could not pause the internet: pf could not be enabled"
        await m.check()
        XCTAssertEqual(m.phase, .trouble(.notSealed))
    }

    func testCopyForNotSealed() {
        XCTAssertEqual(AppStateMachine.status(.trouble(.notSealed)), "I couldn't block the internet. Turn Wi-Fi off, then open Help")
        XCTAssertFalse(AppStateMachine.isOn(.trouble(.notSealed)))
        XCTAssertEqual(AppStateMachine.buttonTitle(.trouble(.notSealed)), "Wake me up")
    }
}

@MainActor
final class AppModelHelperUnreachableTests: XCTestCase {
    func testChinaModeWithAnUnreachableHelperSaysItIsNotBlocked() async {
        let defaults = UserDefaults(suiteName: "np-unreach-\(UUID().uuidString)")!
        defaults.set(true, forKey: "chinaMode")
        let helper = FakeHelper()
        helper.ready = .error("Neon Pup was updated. Press Wake me up again")
        let m = AppModel(helper: helper, makeEngine: { _, _ in FakeEngine() }, probe: FakeProbe(works: true),
                         defaults: defaults, store: InMemoryRoadStore(TestRoads.five), pause: { _ in }, monitorEnabled: false,
                         otherVPN: { nil }, openLoginPage: {})
        await m.reattach()
        XCTAssertEqual(m.phase, .trouble(.notSealed))
    }
}

@MainActor
final class AppModelNotSealedKeepsTryingTests: XCTestCase {
    /// After a failed seal the app must keep asking for the seal, never switch it off by itself.
    func testAFailedSealIsRetriedNotLifted() async {
        let helper = FakeHelper(), engine = FakeEngine()
        engine.delays = ["road-1": 60]
        let m = AppModel(helper: helper, makeEngine: { _, _ in engine }, probe: FakeProbe(works: true),
                         defaults: UserDefaults(suiteName: "np-retry-\(UUID().uuidString)")!,
                         store: InMemoryRoadStore(TestRoads.five), pause: { _ in }, monitorEnabled: false,
                         otherVPN: { nil }, openLoginPage: {})
        await m.wake()
        helper.killSwitchError = "pf refused the rules"
        await m.check()
        XCTAssertEqual(m.phase, .trouble(.notSealed))
        helper.killSwitchError = nil
        let tries = helper.calls.filter { $0 == "killSwitch(on)" }.count
        await m.networkChanged()
        XCTAssertGreaterThan(helper.calls.filter { $0 == "killSwitch(on)" }.count, tries, "the seal must be retried")
        XCTAssertFalse(helper.calls.suffix(3).contains("killSwitch(off)"))
    }
}

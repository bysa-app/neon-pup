import XCTest
@testable import NeonPupKit
@testable import NeonPupCore

@MainActor
final class AppModelTests: XCTestCase {
    var helper: FakeHelper!
    var engine: FakeEngine!
    var defaults: UserDefaults!
    var notes: [String] = []
    var madeEngines: [EngineAccess] = []

    func makeModel(probe: Bool = true) -> AppModel {
        helper = FakeHelper()
        engine = FakeEngine()
        defaults = UserDefaults(suiteName: "neonpup-tests-\(UUID().uuidString)")!
        notes = []
        madeEngines = []
        let eng = engine!
        return AppModel(helper: helper,
                        makeEngine: { [unowned self] port, secret in
                            self.madeEngines.append(EngineAccess(port: port, secret: secret)); return eng },
                        probe: FakeProbe(works: probe), defaults: defaults, store: InMemoryRoadStore(TestRoads.five),
                        pause: { _ in }, notify: { [unowned self] in self.notes.append($0) },
                        monitorEnabled: false, otherVPN: { nil }, openLoginPage: {})
    }

    func testWakeConnects() async {
        let m = makeModel()
        engine.delays = ["road-1": 60]
        await m.wake()
        XCTAssertEqual(m.phase, .connected)
        let calls = helper.calls
        XCTAssertEqual(calls.first, "killSwitch(on)", "nothing may leak while connecting")
        XCTAssertLessThan(calls.firstIndex(of: "start")!, calls.firstIndex(of: "applyTimeZone")!)
        // The helper builds the settings itself; the app only learns how to reach the engine.
        XCTAssertEqual(madeEngines, [EngineAccess(port: 41000, secret: "helper-secret")])
        XCTAssertEqual(defaults.integer(forKey: "engineAPIPort"), 41000)
        XCTAssertEqual(defaults.string(forKey: "engineAPISecret"), "helper-secret")
    }

    func testDoubleWakeStartsOnce() async {
        let m = makeModel()
        engine.delays = ["road-1": 60]
        await m.wake()
        await m.wake()
        XCTAssertEqual(helper.calls.filter { $0 == "start" }.count, 1)
    }

    func testNeedsApproval() async {
        let m = makeModel()
        helper.ready = .needsApproval
        await m.wake()
        XCTAssertEqual(m.phase, .trouble(.needsApproval))
        XCTAssertEqual(helper.openedApproval, 1)
        XCTAssertEqual(helper.startCount, 0)
    }

    func testWakeAfterApprovalConnects() async {
        let m = makeModel()
        helper.ready = .needsApproval
        await m.wake()
        helper.ready = .ready
        engine.delays = ["road-1": 60]
        await m.wake()
        XCTAssertEqual(m.phase, .connected)
    }

    func testStartFailure() async {
        let m = makeModel()
        helper.startError = "FATAL tun: permission denied"
        await m.wake()
        XCTAssertEqual(m.phase, .failed)
        XCTAssertEqual(m.lastError, "FATAL tun: permission denied")
    }

    func testNapStopsAndRestoresTimeZone() async {
        let m = makeModel()
        engine.delays = ["road-1": 60]
        await m.wake()
        await m.nap()
        XCTAssertEqual(m.phase, .off)
        XCTAssertEqual(Array(helper.calls.suffix(3)), ["killSwitch(off)", "stop", "restoreTimeZone"])
    }

    func testPickedRoadUnreachableFallsBackToAuto() async {
        let m = makeModel()
        engine.delays = ["road-1": 60, "auto": 60]
        await m.wake()
        await m.pick("road-4")
        XCTAssertEqual(m.phase, .trouble(.roadClosed))
        XCTAssertEqual(engine.selected.last, "road-1", "her road is down: the fixed order takes over")
        engine.delays["road-4"] = 300
        await m.check()
        XCTAssertEqual(m.phase, .connected)
        XCTAssertEqual(engine.selected.last, "road-4")
    }

    func testPickWhileOffIsAppliedOnWake() async {
        let m = makeModel()
        await m.pick("road-3")
        XCTAssertEqual(m.phase, .off)
        XCTAssertTrue(helper.calls.isEmpty)
        XCTAssertEqual(m.mode, .manual)
        engine.delays = ["road-3": 250]
        await m.wake()
        XCTAssertEqual(m.phase, .connected)
        XCTAssertEqual(engine.selected.last, "road-3")
    }

    func testAllRoadsDownWithInternetNotifiesOnce() async {
        let m = makeModel(probe: true)
        engine.delays = ["road-1": 60]
        await m.wake()
        engine.delays = [:]
        await m.check()
        await m.check()
        XCTAssertEqual(m.phase, .trouble(.allRoadsSleepy))
        XCTAssertEqual(notes, ["All servers are sleepy, I'll keep trying"])
    }

    func testNoInternetDoesNotNotify() async {
        let m = makeModel(probe: false)
        engine.delays = ["road-1": 60]
        await m.wake()
        engine.delays = [:]
        await m.check()
        XCTAssertEqual(m.phase, .trouble(.noInternet))
        XCTAssertTrue(notes.isEmpty)
    }

    func testEngineDiedMeansFailedAndTimeZoneRestored() async {
        let m = makeModel()
        engine.delays = ["road-1": 60]
        await m.wake()
        helper.running = false
        helper.lastError = "the engine stopped twice"
        await m.check()
        XCTAssertEqual(m.phase, .failed)
        XCTAssertEqual(helper.calls.last, "restoreTimeZone")
    }

    func testReattachWithDeadEngineRestoresTimeZone() async {
        let m = makeModel()
        helper.running = false
        await m.reattach()
        XCTAssertEqual(m.phase, .off)
        // A crash can leave the kill switch on; outside China mode, relaunching must turn it off.
        XCTAssertEqual(helper.calls, ["restoreTimeZone", "killSwitch(off)"])
    }

    func testReattachWithLiveEngineConnects() async {
        let m = makeModel()
        defaults.set(23456, forKey: "engineAPIPort")
        defaults.set("s", forKey: "engineAPISecret")
        helper.running = true
        engine.delays = ["road-1": 60]
        await m.reattach()
        XCTAssertEqual(m.phase, .connected)
    }

    func testHelpReportHidesSecrets() async {
        let m = makeModel()
        helper.startError = "FATAL vless \(TestRoads.uuid) rejected"
        await m.wake()
        let report = await m.helpReport(appVersion: "1.0.0")
        XCTAssertFalse(report.contains(TestRoads.uuid))
        XCTAssertTrue(report.contains("state: failed"))
    }
}

/// Quit must not depend on async work being scheduled while AppKit waits to terminate
/// (found in the Task 11 drill: quit while connected hung and left the engine running).
@MainActor
final class AppModelQuitTests: XCTestCase {
    func testQuitStopsSynchronously() async {
        let helper = FakeHelper()
        let engine = FakeEngine()
        engine.delays = ["road-1": 60]
        let model = AppModel(helper: helper, makeEngine: { _, _ in engine }, probe: FakeProbe(works: true),
                             defaults: UserDefaults(suiteName: "np-quit-\(UUID().uuidString)")!,
                             store: InMemoryRoadStore(TestRoads.five), pause: { _ in }, monitorEnabled: false, otherVPN: { nil }, openLoginPage: {})
        await model.wake()
        XCTAssertEqual(model.phase, .connected)
        model.stopForQuit()
        XCTAssertEqual(Array(helper.calls.suffix(2)), ["stopNow", "killSwitch(off)"])
        XCTAssertEqual(model.phase, .off)
    }
}

/// Final review I-1 / I-2: taps and checks that overlap must not leave the Mac changed or report false trouble.
@MainActor
final class AppModelOverlapTests: XCTestCase {
    func make(_ helper: FakeHelper, _ engine: FakeEngine) -> AppModel {
        AppModel(helper: helper, makeEngine: { _, _ in engine }, probe: FakeProbe(works: true),
                 defaults: UserDefaults(suiteName: "np-overlap-\(UUID().uuidString)")!,
                 store: InMemoryRoadStore(TestRoads.five), pause: { _ in await Task.yield() }, monitorEnabled: false, otherVPN: { nil }, openLoginPage: {})
    }

    func testNapDuringConnectingLeavesNothingChanged() async {
        let helper = FakeHelper(), engine = FakeEngine()
        engine.delays = ["road-1": 60]
        let model = make(helper, engine)
        helper.duringStart = { await model.nap() }
        await model.wake()
        XCTAssertEqual(model.phase, .off)
        XCTAssertFalse(helper.calls.contains("applyTimeZone"), "time zone swapped after nap: \(helper.calls)")
        XCTAssertTrue(helper.calls.contains("restoreTimeZone"))
        XCTAssertEqual(helper.calls.last, "killSwitch(off)")
    }

    func testStaleCheckDoesNotReportTroubleAfterReconnect() async {
        let helper = FakeHelper(), engine = FakeEngine()
        engine.delays = ["road-1": 60]
        let model = make(helper, engine)
        await model.wake()
        XCTAssertEqual(model.phase, .connected)
        // While this check waits on the engine, the user naps and wakes again; the old check's "no answer" is stale.
        engine.duringDelay = {
            await model.nap()
            await model.wake()
            engine.failNext = true
        }
        await model.check()
        XCTAssertEqual(model.phase, .connected)
    }

    func testOverlappingChecksRunOneAtATime() async {
        let helper = FakeHelper(), engine = FakeEngine()
        engine.delays = ["road-1": 60]
        let model = make(helper, engine)
        await model.wake()
        helper.maxStatusInFlight = 0
        async let a: Void = model.check()
        async let b: Void = model.check()
        async let c: Void = model.check()
        _ = await (a, b, c)
        XCTAssertEqual(helper.maxStatusInFlight, 1)
        XCTAssertEqual(model.phase, .connected)
    }
}

/// Live drill 2026-10-09: a Wake pressed while launch reattach is still checking must not be undone by it.
@MainActor
final class AppModelReattachRaceTests: XCTestCase {
    func testWakeDuringReattachIsNotUndone() async {
        let helper = FakeHelper(), engine = FakeEngine()
        engine.delays = ["road-1": 60]
        let model = AppModel(helper: helper, makeEngine: { _, _ in engine }, probe: FakeProbe(works: true),
                             defaults: UserDefaults(suiteName: "np-race-\(UUID().uuidString)")!,
                             store: InMemoryRoadStore(TestRoads.five), pause: { _ in }, monitorEnabled: false, otherVPN: { nil }, openLoginPage: {})
        helper.duringStatus = { await model.wake() }
        await model.reattach()
        XCTAssertEqual(model.phase, .connected)
        XCTAssertFalse(helper.calls.contains("stop"), "reattach stopped the user's fresh connection: \(helper.calls)")
        XCTAssertNotEqual(helper.calls.last, "restoreTimeZone")
    }
}

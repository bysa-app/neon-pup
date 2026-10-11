import XCTest
@testable import NeonPupKit
import NeonPupCore

/// Codex full review 2026-10-10, before the China trip: Claude keeps its server, startup doesn't wait on server 1,
/// a failed switch is never "Connected", and a stuck engine gets one controlled reconnect.
@MainActor
final class TripReliabilityTests: XCTestCase {
    private func model(_ h: FakeHelper, _ e: FakeEngine, defaults: UserDefaults? = nil,
                       pauses: (() -> Void)? = nil) -> AppModel {
        AppModel(helper: h, makeEngine: { _, _ in e }, probe: FakeProbe(works: true),
                 defaults: defaults ?? UserDefaults(suiteName: "trip-\(UUID().uuidString)")!,
                 store: InMemoryRoadStore(TestRoads.five), pause: { _ in pauses?() }, monitorEnabled: false,
                 otherVPN: { nil }, openLoginPage: {})
    }

    func testClaudeKeepsItsServerAcrossRestarts() async {
        let h = FakeHelper(), e = FakeEngine(), d = UserDefaults(suiteName: "trip-\(UUID().uuidString)")!
        e.delays = ["road-2": 80]
        let first = model(h, e, defaults: d)
        await first.wake()
        XCTAssertEqual(e.claudeSelected.last, "road-2")
        await first.nap()
        e.delays = ["road-1": 60, "road-2": 80]   // Singapore everyday is back
        let second = model(h, e, defaults: d)
        await second.wake()
        XCTAssertEqual(e.claudeSelected.last, "road-2", "Claude stays where it was working")
    }

    func testOneMissedCheckDoesNotMoveClaude() async {
        let h = FakeHelper(), e = FakeEngine()
        e.delays = ["road-1": 60, "road-2": 80]
        let m = model(h, e)
        await m.wake()
        XCTAssertEqual(e.claudeSelected.last, "road-1")
        e.delays = ["road-2": 80]
        await m.check()
        XCTAssertEqual(e.claudeSelected.last, "road-1", "one miss is a blip")
        await m.check()
        XCTAssertEqual(e.claudeSelected.last, "road-2", "two misses in a row: move on")
    }

    func testClaudeFallsBackToAmericaWithoutAsking() async {
        let h = FakeHelper(), e = FakeEngine()
        e.delays = ["road-3": 200]
        let m = model(h, e)
        await m.wake()
        XCTAssertEqual(e.claudeSelected.last, "road-3")
        XCTAssertEqual(m.phase, .connected)
    }

    func testAFailedSwitchIsNotConnected() async {
        let h = FakeHelper(), e = FakeEngine()
        e.delays = ["road-1": 60]
        e.refuseSelect = true
        let m = model(h, e)
        await m.wake()
        XCTAssertNotEqual(m.phase, .connected)
        XCTAssertNotNil(m.lastError)
    }

    func testStartupDoesNotWaitOnServerOne() async {
        let h = FakeHelper(), e = FakeEngine()
        e.delays = ["road-2": 80]
        e.choiceAnswers = false
        var waits = 0
        let m = model(h, e, pauses: { waits += 1 })
        await m.wake()
        XCTAssertEqual(m.phase, .connected)
        XCTAssertEqual(waits, 0, "server 2 answered at once, so no waiting on server 1")
    }

    func testAStuckEngineGetsOneReconnect() async {
        let h = FakeHelper(), e = FakeEngine()
        e.delays = [:]                          // engine runs, no server answers, ordinary internet works
        let m = model(h, e)
        await m.wake()
        XCTAssertEqual(m.phase, .trouble(.allRoadsSleepy))
        for _ in 0..<4 { await m.check() }
        XCTAssertEqual(h.startCount, 2, "one controlled reconnect")
        for _ in 0..<4 { await m.check() }
        XCTAssertEqual(h.startCount, 2, "not again straight away")
        XCTAssertTrue(h.calls.filter { $0 == "killSwitch(off)" }.isEmpty, "the block is never lifted to reconnect")
    }
}

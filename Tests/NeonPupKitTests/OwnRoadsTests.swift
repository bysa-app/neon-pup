import XCTest
@testable import NeonPupKit
@testable import NeonPupCore

/// Own roads (2026-10-10): the app runs on the person's roads, in their order.
@MainActor
final class OwnRoadsTests: XCTestCase {
    var helper: FakeHelper!
    var engine: FakeEngine!
    func make(_ roads: [RoadSpec]) -> AppModel {
        helper = FakeHelper(); engine = FakeEngine()
        let eng = engine!
        return AppModel(helper: helper, makeEngine: { _, _ in eng }, probe: FakeProbe(works: true),
                        defaults: UserDefaults(suiteName: "np-own-\(UUID().uuidString)")!,
                        store: InMemoryRoadStore(roads), pause: { _ in }, monitorEnabled: false,
                        otherVPN: { nil }, openLoginPage: {})
    }
    var allAlive: [String: Int] { Dictionary(uniqueKeysWithValues: (1...5).map { ("road-\($0)", 60) }) }

    func testNoRoadsMeansAddThemFirstAndNothingStarts() async {
        let m = make([])
        await m.wake()
        XCTAssertEqual(m.phase, .trouble(.noRoads))
        XCTAssertTrue(helper.calls.isEmpty, "\(helper.calls)")
    }

    func testTheHelperGetsTheRoadsInOrder() async {
        let m = make(TestRoads.five)
        engine.delays = allAlive
        await m.wake()
        XCTAssertEqual(helper.startedRoads.last, TestRoads.five)
    }

    func testChangingRoadsWhileConnectedReconnectsAndClaudeFollowsTheNewFirstRoad() async {
        let m = make(TestRoads.five)
        engine.delays = allAlive
        await m.wake()
        let reordered = [TestRoads.five[2], TestRoads.five[0]]
        let ok = await m.setRoads(reordered)
        XCTAssertTrue(ok)
        XCTAssertEqual(helper.startedRoads.last, reordered)
        XCTAssertEqual(m.roads.map(\.name), ["America everyday", "Singapore everyday"])
        XCTAssertEqual(engine.claudeSelected.last, "road-1")
        XCTAssertEqual(m.phase, .connected)
    }

    func testInvalidRoadsAreRefusedAndNotSaved() async {
        let store = InMemoryRoadStore(TestRoads.five)
        let m = AppModel(helper: FakeHelper(), store: store, monitorEnabled: false, otherVPN: { nil }, openLoginPage: {})
        var bad = TestRoads.five[0]; bad.host = "bad host"
        let ok = await m.setRoads([bad])
        XCTAssertFalse(ok)
        XCTAssertEqual(store.roads, TestRoads.five)
        let nine = await m.setRoads(Array(repeating: TestRoads.five[0], count: 9))
        XCTAssertFalse(nine)
    }

    func testAddingRoadsClearsTheAddRoadsMessage() async {
        let m = make([])
        await m.wake()
        await m.setRoads(TestRoads.five)
        XCTAssertEqual(m.phase, .off)
    }

    func testAPickedRoadThatWasDeletedCountsAsNoPick() async {
        let m = make(TestRoads.five)
        await m.pick("road-5")
        await m.setRoads(Array(TestRoads.five.prefix(2)))
        engine.delays = allAlive
        await m.wake()
        XCTAssertEqual(m.phase, .connected, "a missing pick must not read as 'road closed'")
        XCTAssertEqual(engine.selected.last, "road-1")
    }

    func testKeychainRoundTripOnATestOnlyEntry() {
        let store = KeychainRoadStore(service: "co.holinic.neonpup.tests.\(UUID().uuidString)")
        XCTAssertEqual(store.load(), [])
        XCTAssertTrue(store.save(TestRoads.five))
        XCTAssertEqual(store.load(), TestRoads.five)
        // Saving over existing roads re-creates the item with Neon Pup's own access rules (security review).
        XCTAssertTrue(store.save(Array(TestRoads.five.prefix(2))))
        XCTAssertEqual(store.load(), Array(TestRoads.five.prefix(2)))
        XCTAssertTrue(store.save([]))
        XCTAssertEqual(store.load(), [])
    }
}

/// Codex review 2026-10-10, reproduced before fixing.
@MainActor
final class CodexFindingsModelTests: XCTestCase {
    /// Finding 2: changing roads while connected must never lift the kill switch in between.
    func testChangingRoadsWhileConnectedKeepsTheKillSwitchOn() async {
        let helper = FakeHelper(), engine = FakeEngine()
        engine.delays = Dictionary(uniqueKeysWithValues: (1...5).map { ("road-\($0)", 60) })
        let m = AppModel(helper: helper, makeEngine: { _, _ in engine }, probe: FakeProbe(works: true),
                         defaults: UserDefaults(suiteName: "np-cx2-\(UUID().uuidString)")!,
                         store: InMemoryRoadStore(TestRoads.five), pause: { _ in }, monitorEnabled: false,
                         otherVPN: { nil }, openLoginPage: {})
        await m.wake()
        let before = helper.calls.count
        await m.setRoads(Array(TestRoads.five.prefix(2)))
        let during = Array(helper.calls[before...])
        XCTAssertFalse(during.contains("killSwitch(off)"), "\(during)")
        XCTAssertTrue(during.contains("start"))
        XCTAssertEqual(m.phase, .connected)
    }

    /// Finding 3: saving roads while still connecting must end up running the new roads.
    func testSavingRoadsDuringStartStillUsesTheNewRoads() async {
        let helper = FakeHelper(), engine = FakeEngine()
        engine.delays = Dictionary(uniqueKeysWithValues: (1...5).map { ("road-\($0)", 60) })
        let m = AppModel(helper: helper, makeEngine: { _, _ in engine }, probe: FakeProbe(works: true),
                         defaults: UserDefaults(suiteName: "np-cx3-\(UUID().uuidString)")!,
                         store: InMemoryRoadStore(TestRoads.five), pause: { _ in }, monitorEnabled: false,
                         otherVPN: { nil }, openLoginPage: {})
        let newRoads = [TestRoads.five[3]]
        helper.duringStart = { await m.setRoads(newRoads) }
        await m.wake()
        XCTAssertEqual(helper.startedRoads.last, newRoads, "the saved roads never started")
        XCTAssertEqual(m.phase, .connected)
    }
}

/// Security review 2026-10-10 on the Codex fixes.
@MainActor
final class ReconnectStateTests: XCTestCase {
    /// Deleting every road while connected must not leave the Mac sealed behind "Add your roads first".
    func testDeletingAllRoadsWhileConnectedLiftsTheSealOutsideChinaMode() async {
        let helper = FakeHelper(), engine = FakeEngine()
        engine.delays = ["road-1": 60]
        let m = AppModel(helper: helper, makeEngine: { _, _ in engine }, probe: FakeProbe(works: true),
                         defaults: UserDefaults(suiteName: "np-rs-\(UUID().uuidString)")!,
                         store: InMemoryRoadStore(TestRoads.five), pause: { _ in }, monitorEnabled: false,
                         otherVPN: { nil }, openLoginPage: {})
        await m.wake()
        await m.setRoads([])
        XCTAssertEqual(m.phase, .trouble(.noRoads))
        XCTAssertEqual(helper.calls.last, "killSwitch(off)", "\(helper.calls.suffix(4))")
    }
}

/// Fable review 2026-10-10 on own roads.
@MainActor
final class FableOwnRoadsTests: XCTestCase {
    func make(_ roads: [RoadSpec], _ helper: FakeHelper, _ engine: FakeEngine, _ store: InMemoryRoadStore? = nil) -> AppModel {
        AppModel(helper: helper, makeEngine: { _, _ in engine }, probe: FakeProbe(works: true),
                 defaults: UserDefaults(suiteName: "np-fb-\(UUID().uuidString)")!,
                 store: store ?? InMemoryRoadStore(roads), pause: { _ in }, monitorEnabled: false,
                 otherVPN: { nil }, openLoginPage: {})
    }

    /// Important 1: deleting a road above the pick keeps the pick on the same road.
    func testPickFollowsItsRoadWhenTheListChanges() async {
        let helper = FakeHelper(), engine = FakeEngine()
        engine.delays = Dictionary(uniqueKeysWithValues: (1...5).map { ("road-\($0)", 60) })
        let m = make(TestRoads.five, helper, engine)
        await m.pick("road-2")
        await m.setRoads(Array(TestRoads.five.dropFirst()))
        XCTAssertEqual(m.pickedRoad, "road-1", "Singapore turbo is now first and must stay picked")
        await m.setRoads(Array(TestRoads.five.dropFirst(2)))
        XCTAssertNil(m.pickedRoad, "the picked road was deleted")
    }

    /// Minor 7: a second save during a reconnect is not left for a later wake.
    func testTwoQuickSavesEndOnTheLastRoads() async {
        let helper = FakeHelper(), engine = FakeEngine()
        engine.delays = Dictionary(uniqueKeysWithValues: (1...5).map { ("road-\($0)", 60) })
        let m = make(TestRoads.five, helper, engine)
        await m.wake()
        helper.duringStart = { await m.setRoads([TestRoads.five[4]]) }
        await m.setRoads([TestRoads.five[3]])
        XCTAssertEqual(helper.startedRoads.last, [TestRoads.five[4]])
    }
}

final class FableRoadStoreTests: XCTestCase {
    /// Minor 2/3: the cap holds in the store, and one bad stored road does not drop the others.
    func testStoreCapsAndKeepsGoodRoads() {
        let store = KeychainRoadStore(service: "co.holinic.neonpup.tests.\(UUID().uuidString)")
        XCTAssertFalse(store.save(Array(repeating: TestRoads.five[0], count: 9)))
        XCTAssertEqual(KeychainRoadStore.usable([TestRoads.five[0], { var r = TestRoads.five[1]; r.host = "bad host"; return r }()]),
                       [TestRoads.five[0]])
        _ = store.save([])
    }
}

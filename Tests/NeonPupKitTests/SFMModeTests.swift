import XCTest
@testable import NeonPupKit
import NeonPupCore

/// Neon Pup on SFM (2026-10-10): same panel and actions, SFM's NetworkExtension tunnel underneath.
@MainActor
final class SFMModeTests: XCTestCase {
    private func model(_ h: FakeHelper, _ e: FakeEngine, setupNeeded: Bool = false, fingerprint: String? = nil,
                       defaults: UserDefaults? = nil) -> AppModel {
        AppModel(helper: h, makeEngine: { _, _ in e }, probe: FakeProbe(works: true),
                 defaults: defaults ?? UserDefaults(suiteName: "sfm-\(UUID().uuidString)")!,
                 store: InMemoryRoadStore(TestRoads.five), pause: { _ in }, monitorEnabled: false,
                 otherVPN: { nil }, openLoginPage: {},
                 sfm: AppModel.SFMOptions(setupNeeded: { setupNeeded }, fingerprint: { fingerprint }))
    }

    /// Fable re-check A: under SFM the tunnel itself is the protection; a Wi-Fi switch-off that fails must not
    /// stop the start.
    func testStartDoesNotDependOnTheOfflineSwitch() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        h.killSwitchErrorWhenStopped = "could not turn Wi-Fi off"
        let m = model(h, e)
        await m.setChinaMode(true)
        await m.wake()
        XCTAssertEqual(m.phase, .connected)
        XCTAssertEqual(h.startCount, 1)
    }

    /// Codex re-check: a mode that can't be read back is not Connected (it could still be Direct).
    func testUnreadableModeIsNotConnected() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        e.modeUnreadable = true
        let m = model(h, e)
        await m.wake()
        XCTAssertNotEqual(m.phase, .connected)
    }

    /// Codex re-check: the helper's expiry stays armed until the direct window really closed.
    func testExpiryStaysArmedWhenTheWindowWontClose() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let m = model(h, e)
        await m.wake()
        await m.startHotelLogin()
        e.refusedModes = ["Rule"]
        await m.endHotelLogin()
        XCTAssertEqual(h.hotelCancels, 0)
    }

    /// Live test 2026-10-12: the wizard's "start SFM once" left the tunnel running while Neon Pup showed napping.
    /// Finishing setup hands control to Neon Pup: napping means the tunnel is off.
    func testFinishingSetupStopsTheTunnelSFMStarted() async {
        let h = FakeHelper(), e = FakeEngine()
        h.running = true
        let m = model(h, e)
        await m.setupFinished()
        XCTAssertEqual(m.phase, .off)
        XCTAssertFalse(h.running)
    }

    func testFinishingSetupLeavesAConnectionNeonPupStarted() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let m = model(h, e)
        await m.wake()
        await m.setupFinished()
        XCTAssertEqual(m.phase, .connected)
        XCTAssertTrue(h.running)
    }

    /// Live test 2026-10-12: a nap stopped the tunnel; the network change that caused arrived mid-nap, looked
    /// like a drop, and the drop reconnect started it again (in China mode: Wi-Fi back on). China mode on SFM
    /// no longer stops the tunnel, but napping outside it still does.
    func testGoOfflineIsNotUndoneByTheNetworkChangeItCauses() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let m = model(h, e)
        await m.wake()
        XCTAssertEqual(m.phase, .connected)
        h.duringStop = { await m.networkChanged() }
        await m.nap()
        XCTAssertEqual(m.phase, .off)
        XCTAssertFalse(h.running)
        XCTAssertEqual(h.startCount, 1, "nothing may start again after Go offline")
    }

    /// The same change arriving while a reconnect stops the tunnel must not start a second reconnect.
    func testNetworkChangeDuringReconnectStartsOnlyOnce() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let m = model(h, e)
        await m.wake()
        h.duringStop = { await m.networkChanged() }
        await m.setRoads([TestRoads.five[0]])
        XCTAssertEqual(m.phase, .connected)
        XCTAssertEqual(h.startCount, 2)
    }

    /// China mode on SFM: Go offline keeps the tunnel and only goes offline (live test 2026-10-12: stopping it
    /// meant Wake me up had to turn Wi-Fi on before the tunnel existed, and traffic went out directly).
    func testChinaModeGoOfflineKeepsTheTunnel() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let m = model(h, e)
        await m.setChinaMode(true)
        await m.wake()
        await m.nap()
        XCTAssertEqual(m.phase, .off)
        XCTAssertTrue(h.running, "the tunnel stays up")
        XCTAssertEqual(h.offlineCalls, 1)
        await m.wake()
        XCTAssertEqual(m.phase, .connected)
    }

    /// Outside China mode napping still stops the tunnel (normal internet).
    func testNapOutsideChinaModeStopsTheTunnel() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let m = model(h, e)
        await m.wake()
        await m.nap()
        XCTAssertFalse(h.running)
        XCTAssertEqual(h.offlineCalls, 0)
    }

    /// Restarting the app while offline in China mode stays offline (no attach, no Wi-Fi).
    func testRelaunchWhileOfflineStaysOffline() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let d = UserDefaults(suiteName: "sfm-\(UUID().uuidString)")!
        let m = model(h, e, defaults: d)
        await m.setChinaMode(true)
        await m.wake()
        await m.nap()
        let fresh = model(h, e, defaults: d)
        await fresh.reattach()
        XCTAssertEqual(fresh.phase, .off)
        XCTAssertTrue(h.running)
    }

    /// Turning China mode off while offline: the tunnel stops first, then normal internet comes back.
    func testLeavingChinaModeWhileOfflineStopsTheTunnel() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let m = model(h, e)
        await m.setChinaMode(true)
        await m.wake()
        await m.nap()
        await m.setChinaMode(false)
        XCTAssertFalse(h.running)
        XCTAssertEqual(h.calls.suffix(2), ["stop", "killSwitch(off)"])
    }

    /// Live test 2026-10-12: macOS puts the local time zone back a few seconds after the network changes, even
    /// with "set automatically" written off. Neon Pup re-applies Singapore after a network change and on every
    /// check while connected.
    func testTimeZoneIsReappliedAfterANetworkChange() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let m = model(h, e)
        await m.wake()
        let before = h.calls.filter { $0 == "applyTimeZone" }.count
        await m.networkChanged()
        await m.settleTimeZone()
        XCTAssertGreaterThanOrEqual(h.calls.filter { $0 == "applyTimeZone" }.count, before + 2)
    }

    func testTimeZoneIsNotTouchedWhileNapping() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let m = model(h, e)
        await m.wake()
        await m.nap()
        let before = h.calls.filter { $0 == "applyTimeZone" }.count
        await m.networkChanged()
        await m.settleTimeZone()
        XCTAssertEqual(h.calls.filter { $0 == "applyTimeZone" }.count, before)
    }

    /// Codex pre-release #2: a Go offline that could not turn Wi-Fi off is never shown as offline.
    func testFailedGoOfflineIsReported() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let m = model(h, e)
        await m.setChinaMode(true)
        await m.wake()
        h.offlineError = "could not turn Wi-Fi off"
        await m.nap()
        XCTAssertEqual(m.phase, .trouble(.notSealed))
        XCTAssertEqual(m.lastError, "could not turn Wi-Fi off")
    }

    /// Codex pre-release #3: a relaunch that finds Neon Pup's offline flag makes sure Wi-Fi really is off.
    func testRelaunchWhileOfflineEnforcesOffline() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let d = UserDefaults(suiteName: "sfm-\(UUID().uuidString)")!
        let m = model(h, e, defaults: d)
        await m.setChinaMode(true)
        await m.wake()
        await m.nap()
        let calls = h.offlineCalls
        let fresh = model(h, e, defaults: d)
        await fresh.reattach()
        XCTAssertEqual(h.offlineCalls, calls + 1, "Wi-Fi may have been turned on by hand meanwhile")
        XCTAssertEqual(fresh.phase, .off)
    }

    /// Codex pre-release #4: the time zone repair after a network change never runs after Go offline restored
    /// the original zone.
    func testTimeZoneRepairStopsAtNap() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let m = model(h, e)
        await m.wake()
        await m.networkChanged()
        await m.nap()
        await m.settleTimeZone()
        let tz = h.calls.filter { $0.contains("TimeZone") }
        XCTAssertEqual(tz.last, "restoreTimeZone")
    }

    /// Fable pre-release #2: Go offline pressed while Wake me up is still starting keeps the tunnel in China mode.
    func testGoOfflineDuringStartKeepsTheTunnel() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let m = model(h, e)
        await m.setChinaMode(true)
        h.duringStart = { await m.nap() }
        await m.wake()
        XCTAssertEqual(m.phase, .off)
        XCTAssertTrue(h.running, "the tunnel stays up; only Wi-Fi goes off")
    }

    func testWakeBeforeSetupAsksToFinishSetup() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let m = model(h, e, setupNeeded: true)
        await m.wake()
        XCTAssertEqual(m.phase, .trouble(.setupNeeded))
        XCTAssertEqual(h.startCount, 0)
    }

    func testAnOlderServerListInSFMIsNotCalledConnected() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        e.known = ["np-old"]
        let m = model(h, e, fingerprint: "np-new")
        await m.wake()
        XCTAssertEqual(m.phase, .trouble(.profileOutdated))
        XCTAssertTrue(m.isOn, "traffic stays in the tunnel; only the list is old")
        e.known = ["np-new"]
        await m.check()
        XCTAssertEqual(m.phase, .connected)
    }

    func testChinaModeReconnectsWhenTheTunnelDrops() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let m = model(h, e, fingerprint: "np-x"); e.known = ["np-x"]
        await m.setChinaMode(true)
        await m.wake()
        XCTAssertEqual(m.phase, .connected)
        h.running = false                     // SFM's tunnel dropped
        await m.check()
        XCTAssertEqual(h.startCount, 2)
        XCTAssertEqual(m.phase, .connected)
    }

    /// Live test 2026-10-12: outside China mode a drop showed "The connection dropped" while SFM's tunnel was
    /// already back. On SFM every drop reconnects by itself.
    func testOutsideChinaModeADropReconnectsToo() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let m = model(h, e, fingerprint: "np-x"); e.known = ["np-x"]
        await m.wake()
        h.running = false
        await m.check()
        XCTAssertEqual(h.startCount, 2)
        XCTAssertEqual(m.phase, .connected)
    }

    /// Reconnecting stops after three drops in a row; then the panel says so and waits for a tap.
    func testRepeatedDropsEndInDropped() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let m = model(h, e, fingerprint: "np-x"); e.known = ["np-x"]
        await m.wake()
        h.startError = "SFM did not connect"
        h.running = false
        await m.check()
        await m.check()
        await m.check()
        await m.check()
        XCTAssertEqual(m.phase, .failed)
        XCTAssertLessThanOrEqual(h.startCount, 4)
    }

    /// Live test 2026-10-12: on SFM a dropped connection means normal internet, so the panel offers no
    /// "Back to normal internet" and no Wi-Fi login link; Wake me up is the only action.
    func testDroppedOnSFMOffersOnlyWakeMeUp() async {
        let h = FakeHelper(), e = FakeEngine(); h.startError = "SFM did not connect"
        let m = model(h, e)
        await m.wake()
        XCTAssertEqual(m.phase, .failed)
        XCTAssertFalse(m.showsNapLink)
        XCTAssertFalse(m.showsHotelLogin)
        XCTAssertNil(m.panelLink)
    }

    /// The old engine's dropped state used to show two links; now it shows one.
    func testOldEngineDroppedShowsOneLink() async {
        let h = FakeHelper(), e = FakeEngine(); h.startError = "engine died"
        let m = AppModel(helper: h, makeEngine: { _, _ in e }, probe: FakeProbe(works: true),
                         defaults: UserDefaults(suiteName: "sfm-\(UUID().uuidString)")!,
                         store: InMemoryRoadStore(TestRoads.five), pause: { _ in }, monitorEnabled: false,
                         otherVPN: { nil }, openLoginPage: {})
        await m.wake()
        XCTAssertEqual(m.phase, .failed)
        XCTAssertTrue(m.showsNapLink && m.showsHotelLogin, "both used to be shown")
        XCTAssertEqual(m.panelLink, .nap("Back to normal internet"))
    }

    /// The Wi-Fi login link appears on SFM only while the tunnel runs and no server answers (a login page
    /// in the way).
    func testWifiLoginLinkOnlyWhenServersAreBlocked() async {
        let h = FakeHelper(), e = FakeEngine()
        let m = model(h, e)
        await m.wake()
        XCTAssertEqual(m.phase, .trouble(.allRoadsSleepy))
        XCTAssertTrue(m.showsHotelLogin)
        await m.setChinaMode(true)
        await m.nap()
        XCTAssertFalse(m.showsHotelLogin, "napping in China mode means Wi-Fi off: no login page can show")
    }

    func testTunnelChineseSitesIsALiveModeAndTheHotelWindowReturnsToIt() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let m = model(h, e)
        await m.wake()
        XCTAssertEqual(e.modes.last, "Rule")
        await m.setTunnelChinaSites(true)
        XCTAssertEqual(e.modes.last, "Global")
        await m.startHotelLogin()
        XCTAssertEqual(e.modes.last, "Direct")
        XCTAssertEqual(h.hotelExpiries.last?.mode, "Global", "the helper ends the window even if the app is gone")
        XCTAssertEqual(h.hotelExpiries.last?.seconds, 300)
        await m.endHotelLogin()
        XCTAssertEqual(e.modes.last, "Global")
    }

    // Codex review of the built integration (2026-10-10).

    func testHotelWindowOpensOnlyWhenTheHelperArmedItsEnd() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let m = model(h, e)
        await m.wake()
        h.armWorks = false
        await m.startHotelLogin()
        XCTAssertNotEqual(e.modes.last, "Direct", "no direct window without a guaranteed end")
        XCTAssertNotEqual(m.phase, .hotelLogin)
        XCTAssertNotNil(m.lastError)
    }

    func testClosingTheHotelWindowCancelsTheHelpersTimer() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let m = model(h, e)
        await m.wake()
        await m.startHotelLogin()
        await m.endHotelLogin()
        XCTAssertEqual(h.hotelCancels, 1)
    }

    func testAnUnreadableFingerprintIsNeverConnected() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        e.fingerprintUnknown = true
        let m = model(h, e, fingerprint: "np-x")
        await m.wake()
        XCTAssertNotEqual(m.phase, .connected)
    }

    func testAnOlderListIsNotSteered() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60, "road-2": 80]
        e.known = ["np-old"]
        let m = model(h, e, fingerprint: "np-new")
        await m.wake()
        XCTAssertEqual(m.phase, .trouble(.profileOutdated))
        XCTAssertTrue(e.claudeSelected.isEmpty, "road numbers in an older list can mean other servers")
    }

    func testAFailedSwitchWhileConnectedLeavesConnected() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60, "road-2": 80]
        let m = model(h, e)
        await m.wake()
        XCTAssertEqual(m.phase, .connected)
        e.delays = ["road-2": 80]
        await m.check(); await m.check()     // road-1 missed twice: Claude must move
        e.refuseSelect = true
        e.delays = ["road-3": 90]
        await m.check(); await m.check()
        XCTAssertNotEqual(m.phase, .connected)
    }

    func testTheEnginesModeIsReadBackAndRepaired() async {
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let m = model(h, e)
        await m.setTunnelChinaSites(true)
        await m.wake()
        e.reportedMode = "Rule"              // someone or something reset it
        await m.check()
        XCTAssertEqual(e.modes.last, "Global")
        e.reportedMode = "Rule"
        e.refusedModes = ["Global"]
        await m.check()
        XCTAssertNotEqual(m.phase, .connected, "a mode that can't be set is not the protection the user chose")
    }

    func testAFailedStartInChinaModeGoesBackOffline() async {
        let h = FakeHelper(), e = FakeEngine()
        h.startError = "SFM did not connect"
        let m = model(h, e)
        await m.setChinaMode(true)
        await m.wake()
        XCTAssertEqual(m.phase, .failed)
        XCTAssertEqual(h.calls.last, "killSwitch(on)", "back offline after a failed start")
    }

    func testTunnelChineseSitesIsOffByDefaultAndRemembered() async {
        let d = UserDefaults(suiteName: "sfm-\(UUID().uuidString)")!
        let h = FakeHelper(), e = FakeEngine(); e.delays = ["road-1": 60]
        let m = model(h, e, defaults: d)
        XCTAssertFalse(m.tunnelChinaSites)
        await m.setTunnelChinaSites(true)
        XCTAssertTrue(model(h, e, defaults: d).tunnelChinaSites)
    }
}

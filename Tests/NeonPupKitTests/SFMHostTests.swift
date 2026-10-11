import XCTest
@testable import NeonPupKit
import NeonPupCore

/// SFMHost against a simulated macOS (Codex review of the built integration, 2026-10-10): Wi-Fi and tunnel
/// changes are verified, ownership of "Wi-Fi off" is never lost, a start can't be undone by a network callback,
/// and the old firewall block is cleared.
final class FakeMac: @unchecked Sendable {
    var wifiOn = true
    var wifiRefuses = false
    /// false = a Mac with no Wi-Fi at all (network cable only).
    var hasWifi = true
    /// The hardware list or the Wi-Fi power can't be read (the tool failed, not "no Wi-Fi").
    var listingFails = false
    var powerUnreadable = false
    /// Answers for the next status reads, before the simulated state ("" = scutil printed nothing).
    var statusQueue: [String] = []
    var tunnel = "Disconnected"
    /// Polls after a start command before the tunnel says Connected; nil = it never connects.
    var connectsAfter: Int? = 1
    var stopsAfter = 1
    private var pending = 0
    var commands: [String] = []
    let id = "2D7E769E-F522-4E64-B99B-1C1C6F7FBAB7"

    func run(_ path: String, _ args: [String]) -> String {
        let cmd = ([path.split(separator: "/").last.map(String.init) ?? path] + args).joined(separator: " ")
        commands.append(cmd)
        switch (path, args.first ?? "") {
        case ("/usr/sbin/networksetup", "-listallhardwareports"):
            if listingFails { return "" }
            return hasWifi ? "Hardware Port: Wi-Fi\nDevice: en0\n" : "Hardware Port: Ethernet\nDevice: en1\n"
        case ("/usr/sbin/networksetup", "-getairportpower"):
            if powerUnreadable { return "" }
            return "Wi-Fi Power (en0): \(wifiOn ? "On" : "Off")"
        case ("/usr/sbin/networksetup", "-setairportpower"):
            if !wifiRefuses { wifiOn = args.last == "on" }
            return ""
        case ("/usr/sbin/scutil", _):
            if args == ["--nc", "list"] {
                return "* (\(tunnel)) \(id) VPN (io.nekohasekai.sfamt.standalone) \"SFM\" [VPN:io.nekohasekai.sfamt.standalone]"
            }
            if args.count >= 2, args[1] == "start" {
                // Measured 2026-10-12: SFM's tunnel ignores a start while there is no network.
                guard wifiOn || !hasWifi else { return "" }
                tunnel = "Connecting"; pending = connectsAfter ?? .max; return ""
            }
            if args.count >= 2, args[1] == "stop" { tunnel = "Disconnecting"; pending = stopsAfter; return "" }
            if args.count >= 2, args[1] == "status" {
                if !statusQueue.isEmpty { return statusQueue.removeFirst() }
                if tunnel == "Connecting" { if pending <= 0 { tunnel = "Connected" } else { pending -= 1 } }
                else if tunnel == "Disconnecting" { if pending <= 0 { tunnel = "Disconnected" } else { pending -= 1 } }
                return tunnel + "\n"
            }
            return ""
        default:
            return ""
        }
    }
}

@MainActor
final class SFMHostTests: XCTestCase {
    private func host(_ mac: FakeMac, base: FakeHelper? = nil, defaults: UserDefaults? = nil) -> SFMHost {
        SFMHost(base: base ?? FakeHelper(), bridge: SFMBridge(run: mac.run), secret: "s",
                defaults: defaults ?? UserDefaults(suiteName: "host-\(UUID().uuidString)")!, pause: { _ in })
    }

    func testGoOfflineThatFailsIsReported() async {
        let mac = FakeMac(); mac.wifiRefuses = true
        let h = host(mac)
        _ = await h.setChinaMode(true)
        let error = await h.setKillSwitch(true)
        XCTAssertNotNil(error, "Wi-Fi is still on: never claim offline")
    }

    func testWifiThatWontComeBackStaysOurs() async {
        let mac = FakeMac()
        let d = UserDefaults(suiteName: "host-\(UUID().uuidString)")!
        let h = host(mac, defaults: d)
        _ = await h.setChinaMode(true)
        _ = await h.setKillSwitch(true)
        XCTAssertFalse(mac.wifiOn)
        mac.wifiRefuses = true
        _ = await h.setKillSwitch(false)
        XCTAssertFalse(mac.wifiOn)
        mac.wifiRefuses = false
        _ = await h.setKillSwitch(false)
        XCTAssertTrue(mac.wifiOn, "the second try still knows Neon Pup turned it off")
    }

    func testBlockRequestWhileStartingLeavesWifiOn() async {
        let mac = FakeMac(); mac.connectsAfter = nil  // never connects within this check
        let h = host(mac)
        _ = await h.setChinaMode(true)
        h.markStarting(true)
        _ = await h.setKillSwitch(true)
        XCTAssertTrue(mac.wifiOn, "a start is in progress: don't pull Wi-Fi from under it")
        h.markStarting(false)
        _ = await h.setKillSwitch(true)
        XCTAssertFalse(mac.wifiOn)
    }

    func testStopWaitsUntilTheTunnelIsDown() async {
        let mac = FakeMac(); mac.tunnel = "Connected"; mac.stopsAfter = 4
        let h = host(mac)
        await h.stop()
        XCTAssertEqual(mac.tunnel, "Disconnected")
    }

    func testTheOldFirewallBlockIsCleared() async {
        let base = FakeHelper()
        let h = host(FakeMac(), base: base)
        await h.clearLegacyBlock()
        XCTAssertEqual(base.chinaModeSent.last, false)
        XCTAssertEqual(base.calls.last, "killSwitch(off)")
    }

    /// Fable re-check A: a Mac without Wi-Fi has nothing to switch off; that is never an error and never leaves
    /// a "Wi-Fi off" flag behind.
    func testMacWithoutWifiIsNeverStuck() async {
        let mac = FakeMac(); mac.hasWifi = false
        let d = UserDefaults(suiteName: "host-\(UUID().uuidString)")!
        d.set(true, forKey: "sfmWifiOffByNeonPup")  // left over from an older build
        let h = host(mac, defaults: d)
        _ = await h.setChinaMode(true)
        let off = await h.setKillSwitch(true)
        XCTAssertNil(off)
        if case .started = await h.start(roads: []) {} else { XCTFail("a cable-only Mac must still connect") }
        XCTAssertFalse(d.bool(forKey: "sfmWifiOffByNeonPup"))
    }

    /// Fable re-check A: Wi-Fi that refuses to switch off is reported, but Neon Pup did not turn it off, so it
    /// doesn't claim it and a start still works.
    func testWifiThatRefusesToGoOffIsNotClaimed() async {
        let mac = FakeMac(); mac.wifiRefuses = true
        let d = UserDefaults(suiteName: "host-\(UUID().uuidString)")!
        let h = host(mac, defaults: d)
        _ = await h.setChinaMode(true)
        let off = await h.setKillSwitch(true)
        XCTAssertNotNil(off)
        XCTAssertFalse(d.bool(forKey: "sfmWifiOffByNeonPup"))
        if case .started = await h.start(roads: []) {} else { XCTFail("start must not depend on Wi-Fi off") }
    }

    /// Codex re-check: a hardware list that can't be read is not "no Wi-Fi": Neon Pup keeps knowing it turned
    /// Wi-Fi off.
    func testUnreadableHardwareListKeepsOwnership() async {
        let mac = FakeMac()
        let d = UserDefaults(suiteName: "host-\(UUID().uuidString)")!
        let h = host(mac, defaults: d)
        _ = await h.setChinaMode(true)
        _ = await h.setKillSwitch(true)
        XCTAssertFalse(mac.wifiOn)
        mac.listingFails = true
        _ = await h.setKillSwitch(false)
        XCTAssertTrue(d.bool(forKey: "sfmWifiOffByNeonPup"), "still Neon Pup's to turn back on")
        mac.listingFails = false
        _ = await h.setKillSwitch(false)
        XCTAssertTrue(mac.wifiOn)
    }

    /// Codex re-check: a Wi-Fi power that can't be read never counts as "off".
    func testUnreadableWifiPowerIsNeverOffline() async {
        let mac = FakeMac(); mac.powerUnreadable = true
        let h = host(mac)
        _ = await h.setChinaMode(true)
        let error = await h.setKillSwitch(true)
        XCTAssertNotNil(error)
    }

    /// Codex re-check: the old firewall block is cleared on the next start if launch couldn't do it.
    func testOldBlockIsRetriedUntilCleared() async {
        let base = FakeHelper(); base.chinaModeError = "could not reach the helper"
        let h = host(FakeMac(), base: base)
        _ = await h.start(roads: [])
        XCTAssertEqual(base.chinaModeSent, [])
        base.chinaModeError = nil
        _ = await h.start(roads: [])
        XCTAssertEqual(base.chinaModeSent, [false])
        _ = await h.start(roads: [])
        XCTAssertEqual(base.chinaModeSent, [false], "once cleared, not again")
    }

    /// China mode on SFM (live test 2026-10-12): Go offline keeps the tunnel up and only turns Wi-Fi off, so
    /// Wake me up turns Wi-Fi back on into a running tunnel and nothing goes out directly.
    func testGoOfflineKeepsTheTunnelAndWakeOnlyTurnsWifiOn() async {
        let mac = FakeMac(); mac.tunnel = "Connected"
        let h = host(mac)
        _ = await h.setChinaMode(true)
        let error = await h.goOffline()
        XCTAssertNil(error)
        XCTAssertFalse(mac.wifiOn)
        XCTAssertEqual(mac.tunnel, "Connected")
        XCTAssertTrue(h.isOffline)
        let before = mac.commands.filter { $0.contains("scutil --nc start") }.count
        if case .started = await h.start(roads: []) {} else { XCTFail("must start") }
        XCTAssertTrue(mac.wifiOn)
        XCTAssertFalse(h.isOffline)
        XCTAssertEqual(mac.commands.filter { $0.contains("scutil --nc start") }.count, before,
                       "the tunnel was already up: no new start")
    }

    /// With the tunnel down (crash, restart), the start is asked again until Wi-Fi has joined, so the tunnel
    /// comes up the moment it can.
    func testStartIsRetriedUntilTheNetworkIsBack() async {
        let mac = FakeMac(); mac.wifiOn = false
        let d = UserDefaults(suiteName: "host-\(UUID().uuidString)")!
        d.set(true, forKey: "sfmWifiOffByNeonPup")
        let h = host(mac, defaults: d)
        _ = await h.setChinaMode(true)
        if case .started = await h.start(roads: []) {} else { XCTFail("must start once Wi-Fi is on") }
        XCTAssertEqual(mac.tunnel, "Connected")
    }

    /// Codex pre-release #1: a stop still waiting must not retry and tear down a tunnel a newer start brought up.
    func testAStartDuringAStopIsNotUndoneByIt() async {
        let mac = FakeMac(); mac.tunnel = "Connected"; mac.stopsAfter = 1000
        var h: SFMHost!
        var hooked = false
        h = SFMHost(base: FakeHelper(), bridge: SFMBridge(run: mac.run), secret: "s",
                    defaults: UserDefaults(suiteName: "host-\(UUID().uuidString)")!, pause: { _ in
            guard !hooked else { return }
            hooked = true
            mac.tunnel = "Disconnected"        // the first stop went through...
            _ = await h.start(roads: [])       // ...and Wake me up started a new tunnel meanwhile
        })
        await h.stop()
        XCTAssertEqual(mac.tunnel, "Connected", "the old stop must not retry against the new tunnel")
    }

    /// Fable pre-release #1: one empty status read is not a drop, and Reasserting is a tunnel recovering.
    /// Security review: a status that stays unreadable is down (fail closed).
    func testAnUnclearStatusReadIsNotADrop() async {
        let mac = FakeMac(); mac.tunnel = "Connected"
        let h = host(mac)
        mac.statusQueue = [""]
        let empty = await h.status()
        XCTAssertTrue(empty.running)
        mac.statusQueue = ["Reasserting\n", "Reasserting\n"]
        let reasserting = await h.status()
        XCTAssertTrue(reasserting.running)
        mac.statusQueue = ["", ""]
        let unreadable = await h.status()
        XCTAssertFalse(unreadable.running)
        mac.tunnel = "Disconnected"
        let down = await h.status()
        XCTAssertFalse(down.running)
    }

    /// Fable pre-release #1: one unclear read never switches Wi-Fi off under a healthy tunnel in China mode;
    /// one that stays unreadable does.
    func testAnUnclearStatusReadDoesNotCutWifi() async {
        let mac = FakeMac(); mac.tunnel = "Connected"
        let h = host(mac)
        _ = await h.setChinaMode(true)
        mac.statusQueue = [""]
        _ = await h.setKillSwitch(true)
        XCTAssertTrue(mac.wifiOn)
        mac.statusQueue = ["", ""]
        _ = await h.setKillSwitch(true)
        XCTAssertFalse(mac.wifiOn, "a status that stays unreadable fails closed")
    }

    /// Fable re-check item 5: the real default wait, not an injected one, outlasts cancellation.
    func testSteadySleepIgnoresCancellation() async {
        let began = Date()
        let task = Task { await SFMHost.steadySleep(300_000_000) }
        task.cancel()
        await task.value
        XCTAssertGreaterThan(Date().timeIntervalSince(began), 0.25)
    }

    func testWaitsAreNotCutShortByCancellation() async {
        let mac = FakeMac(); mac.connectsAfter = 2
        var slept = 0
        let h = SFMHost(base: FakeHelper(), bridge: SFMBridge(run: mac.run), secret: "s",
                        defaults: UserDefaults(suiteName: "host-\(UUID().uuidString)")!,
                        pause: { _ in slept += 1 })
        let task = Task { @MainActor in await h.start(roads: []) }
        task.cancel()
        if case .started = await task.value {} else { XCTFail("a cancelled caller must not make the start fail early") }
        XCTAssertGreaterThan(slept, 0)
    }
}

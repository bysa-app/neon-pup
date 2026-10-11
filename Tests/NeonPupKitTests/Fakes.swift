import Foundation
@testable import NeonPupKit
import NeonPupCore

@MainActor
final class FakeHelper: HelperControlling {
    var ready: HelperReadiness = .ready
    var startError: String?
    var running = false
    var lastError: String?
    var calls: [String] = []
    var startCount = 0
    var access = EngineAccess(port: 41000, secret: "helper-secret")
    var openedApproval = 0

    func readiness() -> HelperReadiness { ready }
    func openApproval() { openedApproval += 1 }
    /// Runs inside start(), to interleave other taps with a slow connect.
    var duringStart: (@MainActor () async -> Void)?
    var statusInFlight = 0
    var maxStatusInFlight = 0

    var startedRoads: [[RoadSpec]] = []
    func start(roads: [RoadSpec]) async -> StartResult {
        calls.append("start"); startCount += 1; startedRoads.append(roads)
        if let duringStart { self.duringStart = nil; await duringStart() }
        if let startError { return .failed(startError) }
        running = true
        return .started(access)
    }
    /// Runs once after the next stop() took effect, before its reply arrives: a tap during a reconnect.
    /// (The real helper runs requests one at a time, so this stop finishes before any later start.)
    var duringStop: (@MainActor () async -> Void)?
    func stop() async {
        calls.append("stop")
        running = false
        if let hook = duringStop { duringStop = nil; await hook() }
    }
    /// Runs once inside the next status() call (e.g. the user taps Wake while launch reattach is checking).
    var duringStatus: (@MainActor () async -> Void)?

    func status() async -> (running: Bool, lastError: String?) {
        if let hook = duringStatus { duringStatus = nil; await hook() }
        statusInFlight += 1
        maxStatusInFlight = max(maxStatusInFlight, statusInFlight)
        await Task.yield()
        statusInFlight -= 1
        return (running, lastError)
    }
    func applyTimeZone() async -> String? { calls.append("applyTimeZone"); return nil }
    func restoreTimeZone() async { calls.append("restoreTimeZone") }
    func stopNow(keepKillSwitch: Bool) {
        calls.append("stopNow"); running = false
        if !keepKillSwitch { calls.append("killSwitch(off)") }
    }
    var log = ""
    func recentLog() async -> String { log }
    var hotelExpiries: [(seconds: Int, mode: String)] = []
    /// false = the helper refuses to arm (unreachable).
    var armWorks = true
    var hotelCancels = 0
    func armHotelExpiry(seconds: Int, apiPort: Int, secret: String, mode: String) async -> Bool {
        hotelExpiries.append((seconds, mode)); return armWorks
    }
    func cancelHotelExpiry() async { hotelCancels += 1 }
    var chinaModeSent: [Bool] = []
    /// Non-nil: the helper can't be reached when China mode is sent.
    var chinaModeError: String?
    /// Runs once inside the next setChinaMode call (a tap while it is in flight).
    var duringChinaMode: (@MainActor () async -> Void)?
    func setChinaMode(_ on: Bool) async -> String? {
        if let hook = duringChinaMode { duringChinaMode = nil; await hook() }
        if let chinaModeError { return chinaModeError }
        chinaModeSent.append(on); return nil
    }
    /// Go offline (China mode on SFM): Wi-Fi off, tunnel untouched.
    var offlineCalls = 0
    var isOffline = false
    var offlineError: String?
    func goOffline() async -> String? {
        offlineCalls += 1
        if let offlineError { return offlineError }
        isOffline = true; return nil
    }
    var killSwitchError: String?
    /// Like SFMHost: the switch-off fails, but only while no tunnel runs (connected = nothing to do).
    var killSwitchErrorWhenStopped: String?
    var duringKillSwitch: (@MainActor () async -> Void)?
    func setKillSwitch(_ on: Bool) async -> String? {
        calls.append(on ? "killSwitch(on)" : "killSwitch(off)")
        if on, let hook = duringKillSwitch { duringKillSwitch = nil; await hook() }
        if on, !running, let killSwitchErrorWhenStopped { return killSwitchErrorWhenStopped }
        return on ? killSwitchError : nil
    }
}

final class FakeEngine: EngineControlling, @unchecked Sendable {
    var delays: [String: Int] = [:]
    /// What the "choice" selector was pointed at, in order.
    var selected: [String] = []
    /// What the "claude" selector was pointed at, in order.
    var claudeSelected: [String] = []
    /// Runs once inside the next delay() call, to interleave taps with a check in flight.
    var duringDelay: (@MainActor () async -> Void)?
    /// The next answer is "no answer" (a stale result from before a reconnect).
    var failNext = false
    func delay(of name: String) async -> Int? {
        if let hook = duringDelay { duringDelay = nil; await hook() }
        if failNext { failNext = false; return nil }
        // Like the real engine at start: "choice" points at server 1, so it answers only if server 1 does.
        if name == "choice", !choiceAnswers { return delays["road-1"] }
        if name == "choice" || name == "auto" { return delays[name] ?? delays.values.first }
        return delays[name]
    }
    /// Outbound names the running config has; nil = every name is known.
    var known: Set<String>?
    /// true: the control API doesn't answer the fingerprint question (timeout, wrong secret).
    var fingerprintUnknown = false
    func knows(_ name: String) async -> Bool? {
        if fingerprintUnknown { return nil }
        return known.map { $0.contains(name) } ?? true
    }
    /// The mode the engine reports; nil = the last one set.
    var reportedMode: String?
    /// true: the control API doesn't say which mode runs.
    var modeUnreadable = false
    func currentMode() async -> String? { modeUnreadable ? nil : (reportedMode ?? modes.last) }
    /// Engine modes set ("Rule" normally, "Direct" during the hotel login window), in order.
    var modes: [String] = []
    /// Modes the engine refuses to switch to (a failed API call).
    var refusedModes: Set<String> = []
    func setMode(_ mode: String) async -> Bool {
        guard !refusedModes.contains(mode) else { return false }
        modes.append(mode); return true
    }

    /// false: "choice" answers only when server 1 does (the real engine before the first switch).
    var choiceAnswers = true
    /// The engine refuses selector changes (a failed API call).
    var refuseSelect = false
    func select(_ name: String, in group: String) async -> Bool {
        if refuseSelect { return false }
        if group == "claude" { claudeSelected.append(name) } else { selected.append(name) }
        return true
    }
}

struct FakeProbe: DirectProbing {
    var works: Bool
    func directInternetWorks() async -> Bool { works }
}

/// Five valid roads in today's order: SG everyday, SG turbo, US everyday, US turbo, secret tunnel
/// (tags road-1 ... road-5). Fake values in the right formats.
enum TestRoads {
    static let uuid = "11111111-2222-4333-8444-555555555555"
    static let key = String(repeating: "A", count: 43)
    static let five: [RoadSpec] = [
        RoadSpec(kind: .reality, name: "Singapore everyday", host: "192.0.2.1", port: 443, uuid: uuid,
                 serverName: "www.apple.com", publicKey: key, shortID: "ab", fingerprint: "chrome"),
        RoadSpec(kind: .hysteria2, name: "Singapore turbo", host: "192.0.2.1", port: 443, password: "hy2-secret-pass"),
        RoadSpec(kind: .reality, name: "America everyday", host: "192.0.2.2", port: 443, uuid: uuid,
                 serverName: "www.apple.com", publicKey: key, shortID: "ab", fingerprint: "chrome"),
        RoadSpec(kind: .hysteria2, name: "America turbo", host: "192.0.2.2", port: 443, password: "hy2-secret-pass"),
        RoadSpec(kind: .websocket, name: "Secret tunnel", host: "example.com", port: 8443, uuid: uuid,
                 serverName: "example.com", path: "/ws-secret-path"),
    ]
}

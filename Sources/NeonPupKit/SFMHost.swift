import Foundation
import NeonPupCore

/// Neon Pup on SFM (2026-10-10): plugs SFM's NetworkExtension tunnel in where Neon Pup's own engine sat, so the
/// panel, modes, Claude logic and checks run unchanged. Neon Pup's helper still does the time zone swap, the
/// hotel expiry and installing SFM. There is no firewall block: SFM's "Include All Networks" keeps traffic in
/// the tunnel while it runs, and China mode's "Go offline" turns Wi-Fi off, which is offline for real.
@MainActor
public final class SFMHost: HelperControlling {
    public let base: HelperControlling
    public let bridge: SFMBridge
    private let secret: String
    private let defaults: UserDefaults
    private var chinaMode = false
    private var lastError: String?
    private let pause: (UInt64) async -> Void
    static let wifiOffKey = "sfmWifiOffByNeonPup"

    public init(base: HelperControlling, bridge: SFMBridge, secret: String, defaults: UserDefaults = .standard,
                pause: @escaping (UInt64) async -> Void = SFMHost.steadySleep) {
        self.base = base; self.bridge = bridge; self.secret = secret; self.defaults = defaults; self.pause = pause
    }

    /// Wi-Fi was turned off by Neon Pup ("Go offline"), remembered across restarts so it comes back on.
    private var wifiOffByUs: Bool {
        get { defaults.bool(forKey: Self.wifiOffKey) }
        set { defaults.set(newValue, forKey: Self.wifiOffKey) }
    }

    /// A wait that a cancelled caller can't cut short (a reconnect started from a cancelled monitor still
    /// waits for SFM; Codex review of the built integration).
    public static func steadySleep(_ nanoseconds: UInt64) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(Int(nanoseconds))) { done.resume() }
        }
    }

    /// A start is in progress: a block request (e.g. from a network-change callback) must not turn Wi-Fi off
    /// under it.
    private var starting = false
    func markStarting(_ on: Bool) { starting = on }

    /// The old Neon Pup engine's firewall block and China flag must not outlive the move to SFM. Tried at launch
    /// and again before each start until the helper confirms both.
    private var legacyCleared = false
    public func clearLegacyBlock() async {
        guard !legacyCleared else { return }
        guard await base.setChinaMode(false) == nil else { return }
        legacyCleared = await base.setKillSwitch(false) == nil
    }

    public func readiness() -> HelperReadiness { base.readiness() }
    public func openApproval() { base.openApproval() }

    public func start(roads: [RoadSpec]) async -> StartResult {
        startsBegun += 1
        starting = true
        defer { starting = false }
        await clearLegacyBlock()
        guard await wifiBackOn() else { return .failed("couldn't turn Wi-Fi back on") }
        guard bridge.serviceID() != nil else { return .failed("finish setting up first") }
        // The tunnel ignores a start until Wi-Fi has joined a network (measured 2026-10-12): ask again every
        // half second, so it comes up the moment it can.
        for _ in 0..<40 {
            let state = bridge.connection()
            if state == .connected || state == .connecting { break }
            bridge.start()
            await pause(500_000_000)
        }
        for _ in 0..<30 {
            if bridge.connection() == .connected {
                lastError = nil
                return .started(EngineAccess(port: SFMStatus.apiPort, secret: secret))
            }
            await pause(1_000_000_000)
        }
        lastError = "SFM did not connect"
        return .failed("SFM did not connect")
    }

    /// Counts starts, so a stop that is still waiting can tell a newer start brought the tunnel up meanwhile.
    private var startsBegun = 0

    /// Returns once the tunnel is really down (asks twice, waits up to about 15 seconds). Gives up as soon as a
    /// newer start begins: retrying would tear down the new tunnel (Codex pre-release #1).
    public func stop() async {
        let mine = startsBegun
        for _ in 0..<2 {
            guard startsBegun == mine else { return }
            bridge.stop()
            for _ in 0..<20 {
                guard startsBegun == mine else { return }
                let state = bridge.connection()
                if state == .disconnected || state == .unknown { return }
                await pause(500_000_000)
            }
        }
        lastError = "SFM didn't stop"
    }

    /// Down = Disconnected or unreadable on two reads a second apart. One empty scutil read must not make Neon Pup
    /// stop a healthy tunnel (Fable pre-release #1); an unreadable state that stays unreadable counts as down, so
    /// a broken status never hides a dead tunnel (security review: fail closed).
    public func status() async -> (running: Bool, lastError: String?) {
        guard bridge.serviceID() != nil else { return (false, lastError) }
        func up(_ c: SFMStatus.Connection) -> Bool { c != .disconnected && c != .unknown }
        if up(bridge.connection()) { return (true, lastError) }
        await pause(1_000_000_000)
        return (up(bridge.connection()), lastError)
    }
    public func applyTimeZone() async -> String? { await base.applyTimeZone() }
    public func restoreTimeZone() async { await base.restoreTimeZone() }

    /// Quit: in China mode the tunnel keeps running (quitting Neon Pup never drops protection there).
    public func stopNow(keepKillSwitch: Bool) {
        // The old engine never runs under SFM: never leave its firewall block behind.
        base.stopNow(keepKillSwitch: false)
        guard !keepKillSwitch else { return }
        bridge.stop()
        if wifiOffByUs, bridge.setWifi(true) { wifiOffByUs = false }
    }

    /// "On" with the tunnel down in China mode means offline: Wi-Fi off. "Off" brings Wi-Fi back if we took it.
    public func setKillSwitch(_ on: Bool) async -> String? {
        if on {
            // No Wi-Fi at all (cable only): nothing to switch off. The guide says to unplug the cable.
            guard chinaMode, !starting, !bridge.hasNoWifi(), bridge.wifiIsOn() else { return nil }
            // Only with the tunnel confirmed down (two reads, see status()): one unclear read must not cut Wi-Fi
            // under a healthy tunnel.
            guard await !status().running, !starting else { return nil }
            // Ownership first: even a half-done switch-off must be undone later.
            wifiOffByUs = true
            if bridge.setWifi(false) { return nil }
            // Seen still on: Neon Pup changed nothing, so it has nothing to restore.
            if bridge.wifiPower() == true { wifiOffByUs = false }
            return "could not turn Wi-Fi off"
        }
        return await wifiBackOn() ? nil : "could not turn Wi-Fi back on"
    }

    public func setChinaMode(_ on: Bool) async -> String? { chinaMode = on; return nil }
    public func recentLog() async -> String { "" }

    public func armHotelExpiry(seconds: Int, apiPort: Int, secret: String, mode: String) async -> Bool {
        await base.armHotelExpiry(seconds: seconds, apiPort: apiPort, secret: secret, mode: mode)
    }

    public func cancelHotelExpiry() async { await base.cancelHotelExpiry() }

    public func installSFM() async -> String? { await base.installSFM() }

    /// China mode "Go offline": Wi-Fi off with the tunnel left running, so Wake me up only turns Wi-Fi back on
    /// into a tunnel that is already up (measured 2026-10-12: nothing goes out directly that way, while a
    /// tunnel can't start without a network).
    public func goOffline() async -> String? {
        guard !bridge.hasNoWifi(), bridge.wifiIsOn() else { return nil }
        wifiOffByUs = true
        if bridge.setWifi(false) { return nil }
        if bridge.wifiPower() == true { wifiOffByUs = false }
        return "could not turn Wi-Fi off"
    }

    public var isOffline: Bool { wifiOffByUs }

    /// true when Wi-Fi is on (or was never ours to turn on). Ownership is kept until it really is on.
    private func wifiBackOn() async -> Bool {
        guard wifiOffByUs else { return true }
        // No Wi-Fi on this Mac (any more): nothing to turn back on.
        guard !bridge.hasNoWifi() else { wifiOffByUs = false; return true }
        guard bridge.setWifi(true) else { lastError = "could not turn Wi-Fi back on"; return false }
        wifiOffByUs = false
        return true
    }
}

import Foundation
import NeonPupCore

public enum HelperReadiness: Equatable {
    case ready, needsApproval, error(String)
}

@MainActor
public protocol HelperControlling: AnyObject {
    func readiness() -> HelperReadiness
    func openApproval()
    func start(roads: [RoadSpec]) async -> StartResult
    func stop() async
    func status() async -> (running: Bool, lastError: String?)
    func applyTimeZone() async -> String?
    func restoreTimeZone() async
    /// Blocking stop + time zone restore, for app termination (no async scheduling needed).
    func stopNow(keepKillSwitch: Bool)
    /// Kill switch on (or refreshed) / off. nil = done.
    func setKillSwitch(_ on: Bool) async -> String?
    /// Tells the helper whether China mode is on (a block survives a restart only then). nil = done.
    func setChinaMode(_ on: Bool) async -> String?
    /// The engine's recent log, for the help report. "" when unavailable.
    func recentLog() async -> String
    /// After `seconds`, the helper sets the engine back to `mode` even if the app is gone (hotel window).
    /// true = armed; the app opens the hotel window only then.
    func armHotelExpiry(seconds: Int, apiPort: Int, secret: String, mode: String) async -> Bool
    func cancelHotelExpiry() async
    /// Installs the pinned SFM release (checked by SHA-256 and signature). nil = installed.
    func installSFM() async -> String?
    /// China mode "Go offline" on SFM: no network at all, the tunnel left running. nil = done.
    func goOffline() async -> String?
    /// true while Neon Pup has the Mac offline (China mode).
    var isOffline: Bool { get }
}

public extension HelperControlling {
    func armHotelExpiry(seconds: Int, apiPort: Int, secret: String, mode: String) async -> Bool { true }
    func cancelHotelExpiry() async {}
    func installSFM() async -> String? { "not available" }
    func goOffline() async -> String? { await setKillSwitch(true) }
    var isOffline: Bool { false }
}

public protocol EngineControlling: Sendable {
    /// Delay in ms through `name` (a road tag, "auto" or "choice"), nil when it does not answer.
    func delay(of name: String) async -> Int?
    /// Points a selector ("choice" or "claude") at `name`. Returns false when the engine refused.
    func select(_ name: String, in group: String) async -> Bool
    /// Engine mode: "Rule" normally, "Direct" during the hotel login window (Claude still on its roads).
    func setMode(_ mode: String) async -> Bool
    /// true when the running config has an outbound called `name` (the server-list fingerprint), nil = no answer.
    func knows(_ name: String) async -> Bool?
    /// The engine's current mode, nil = no answer.
    func currentMode() async -> String?
}

public extension EngineControlling {
    func knows(_ name: String) async -> Bool? { true }
    func currentMode() async -> String? { nil }
}

public protocol DirectProbing: Sendable {
    func directInternetWorks() async -> Bool
}

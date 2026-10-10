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
    /// The engine's recent log, for the help report. "" when unavailable.
    func recentLog() async -> String
}

public protocol EngineControlling: Sendable {
    /// Delay in ms through `name` (a road tag, "auto" or "choice"), nil when it does not answer.
    func delay(of name: String) async -> Int?
    /// Points a selector ("choice" or "claude") at `name`. Returns false when the engine refused.
    func select(_ name: String, in group: String) async -> Bool
    /// Engine mode: "Rule" normally, "Direct" during the hotel login window (Claude still on its roads).
    func setMode(_ mode: String) async -> Bool
}

public protocol DirectProbing: Sendable {
    func directInternetWorks() async -> Bool
}

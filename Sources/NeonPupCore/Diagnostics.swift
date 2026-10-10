import Foundation

public struct DiagnosticFacts: Sendable {
    public var appVersion, macOSVersion, cpu, phase, mode: String
    public var pickedRoad: String?
    public var roadDelays: [String: Int]
    public var lastError: String?
    public var helper: String
    public init(appVersion: String, macOSVersion: String, cpu: String, phase: String, mode: String,
                pickedRoad: String?, roadDelays: [String: Int], lastError: String?, helper: String) {
        self.appVersion = appVersion; self.macOSVersion = macOSVersion; self.cpu = cpu; self.phase = phase
        self.mode = mode; self.pickedRoad = pickedRoad; self.roadDelays = roadDelays; self.lastError = lastError
        self.helper = helper
    }
}

public enum Diagnostics {

    public static func report(_ f: DiagnosticFacts, roads: [Road], redacting secrets: [String]) -> String {
        var lines = [
            "Neon Pup help report",
            "app \(f.appVersion), macOS \(f.macOSVersion), \(f.cpu)",
            "state: \(f.phase), mode: \(f.mode), picked: \(f.pickedRoad ?? "none")",
            "helper: \(f.helper)",
            "roads:",
        ]
        for road in roads {
            lines.append("  \(road.name): " + (f.roadDelays[road.tag].map { "\($0) ms" } ?? "no answer"))
        }
        lines.append("last problem: \(f.lastError ?? "none")")
        var text = lines.joined(separator: "\n")
        for secret in secrets.sorted(by: { $0.count > $1.count }) where secret.count >= 6 {
            text = text.replacingOccurrences(of: secret, with: "<hidden>")
        }
        return text
    }

    /// Everything in the roads that must never appear in a report.
    public static func secrets(from roads: [RoadSpec]) -> [String] {
        Array(Set(roads.flatMap { r in
            [r.uuid, r.password, r.obfsPassword, r.publicKey, r.shortID, r.path, r.publicKeySHA256].compactMap { $0 }
        }))
    }
}

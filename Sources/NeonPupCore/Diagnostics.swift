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

    /// Opens the report so it can be pasted straight into Claude (or any assistant) for troubleshooting.
    public static let claudeIntro = """
        I use Neon Pup, a Mac menu bar app that sends all of my Mac's internet through my own servers using \
        sing-box (VLESS Reality, Hysteria2 or VLESS over WebSocket) on a TUN interface, with a pf firewall block \
        when it is not connected. Something isn't working. Below is its report and its recent log. Please tell me \
        what is wrong and give me steps I can follow. Server addresses and passwords are hidden.
        """

    public static func report(_ f: DiagnosticFacts, roads: [Road], log: String = "", redacting secrets: [String]) -> String {
        var lines = [
            claudeIntro,
            "",
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
        lines.append("")
        lines.append("recent engine log:")
        lines.append(log.isEmpty ? "  (empty)" : log)
        var text = lines.joined(separator: "\n")
        // Secrets first and ignoring case (security review 2026-10-10, round 2): masking first could split a
        // secret that holds something IP-shaped, and hosts reach the log in any case.
        for secret in secrets.sorted(by: { $0.count > $1.count }) where secret.count >= 6 {
            text = text.replacingOccurrences(of: secret, with: "<hidden>", options: .caseInsensitive)
        }
        // Then every address left, anywhere in the report (the last problem line can name one too).
        return maskAddresses(text)
    }

    /// Masks every IPv4 and IPv6 address. A server given as a domain appears in the log by its resolved address,
    /// which the per-link secrets cannot know (security review 2026-10-10).
    static func maskAddresses(_ text: String) -> String {
        let v4 = #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#
        // IPv6 only in real shapes (eight groups, or "::"), so times like 12:34:56 and ports like :443: survive.
        let h = "[0-9A-Fa-f]{1,4}"
        let v6 = "(?<![\\w:])(?:\(h)(?::\(h)){7}|(?:\(h)(?::\(h)){0,6})?::(?:\(h)(?::\(h)){0,6})?)(?![\\w:])"
        return text.replacingOccurrences(of: v4, with: "<address>", options: .regularExpression)
            .replacingOccurrences(of: v6, with: "<address>", options: .regularExpression)
    }

    /// Everything in the roads that must never appear in a report.
    public static func secrets(from roads: [RoadSpec]) -> [String] {
        Array(Set(roads.flatMap { r in
            // The host too: the log names server addresses, and the report goes to an assistant (2026-10-10).
            [r.host, r.uuid, r.password, r.obfsPassword, r.publicKey, r.shortID, r.path, r.publicKeySHA256].compactMap { $0 }
        }))
    }
}

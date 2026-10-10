import Foundation

/// Reads `route -n get` output to decide whether the tunnel carries the Mac's internet traffic. The helper
/// lifts the seal only on a yes. Codex review #4 (2026-10-10): one or two probe addresses could be carried by
/// host routes while everything else went direct, so the probes are spread over the address space and
/// include Claude's own addresses, and every one must go into the tunnel.
public enum RouteCheck {
    /// Cloudflare, Google, AWS, Anthropic (160.79.104.0/23) and Alibaba's DNS in China.
    public static let v4Probes = ["1.1.1.1", "8.8.4.4", "54.230.0.1", "160.79.104.10", "223.5.5.5"]
    /// Cloudflare and Anthropic (2607:6bc0::/48).
    public static let v6Probes = ["2606:4700:4700::1111", "2607:6bc0::10"]

    public static func v4Carried(_ outputs: [String], tunnel: String) -> Bool {
        !outputs.isEmpty && outputs.allSatisfy { interface(in: $0) == tunnel }
    }

    /// No IPv6 route at all is fine, but only when route says so ("not in table"); any other failure is not
    /// proof of absence.
    public static func v6CarriedOrAbsent(_ outputs: [String], tunnel: String) -> Bool {
        !outputs.isEmpty && outputs.allSatisfy { output in
            if let name = interface(in: output) { return name == tunnel }
            return output.contains("not in table")
        }
    }

    static func interface(in output: String) -> String? {
        output.split(separator: "\n").lazy.map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("interface: ") }
            .map { String($0.dropFirst("interface: ".count)) }
    }
}

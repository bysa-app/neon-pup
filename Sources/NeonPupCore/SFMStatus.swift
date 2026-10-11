import Foundation

/// Neon Pup runs on SFM, sing-box's own NetworkExtension app (2026-10-10): macOS then sends every lookup and
/// every app through the tunnel, which Neon Pup's plain tunnel could not do. These read what macOS reports
/// about SFM; the pinned version and checksum live here so the helper and the wizard agree.
public enum SFMStatus {
    public static let teamID = "P8XK3KHB48"
    public static let appBundleID = "io.nekohasekai.sfamt.standalone"
    public static let extensionBundleID = "io.nekohasekai.sfamt.system"
    public static let appPath = "/Applications/SFM.app"
    /// The tested release. The helper installs exactly this package (checked by SHA-256 and signature).
    public static let pinnedVersion = "1.14.3"
    public static let packageURL = "https://github.com/SagerNet/sing-box/releases/download/v1.14.3/SFM-1.14.3-Universal.pkg"
    public static let packageSHA256 = "69f7a5ecc23cf15e97c2fd290ffc67164ae9cec9b820fa01e58184e2803cb7f3"
    /// Neon Pup's control port and profile address inside SFM's engine (127.0.0.1 only).
    public static let apiPort = 47321
    public static let profilePort = 47322
    /// Code requirement for the SFM app: SFM's bundle id, signed by its Developer ID team.
    public static let appRequirement = "anchor apple generic and identifier \"\(appBundleID)\""
        + " and certificate leaf[subject.OU] = \"\(teamID)\""

    public enum ExtensionState: Equatable, Sendable { case missing, waitingForUser, enabled }
    /// `reasserting`: the tunnel is recovering after a network change (still up). `unknown`: unreadable.
    public enum Connection: Equatable, Sendable { case connected, connecting, reasserting, disconnected, disconnecting, unknown }

    /// From `systemextensionsctl list`: SFM's extension, by bundle id AND team.
    public static func extensionState(_ output: String) -> ExtensionState {
        let line = output.split(separator: "\n").last { $0.contains(extensionBundleID) && $0.contains(teamID) }
        guard let line else { return .missing }
        if line.contains("[activated enabled]") { return .enabled }
        if line.contains("waiting for user") { return .waitingForUser }
        return .missing
    }

    /// From `scutil --nc list`: the service id of SFM's VPN, matched by its provider, never by the editable name.
    public static func vpnService(_ output: String) -> String? {
        for line in output.split(separator: "\n") where line.contains("[VPN:\(appBundleID)]") {
            let words = line.split(separator: " ")
            if let id = words.first(where: { $0.count == 36 && $0.filter { $0 == "-" }.count == 4 }) { return String(id) }
        }
        return nil
    }

    /// From `scutil --nc status <id>`: the first line.
    public static func connection(_ output: String) -> Connection {
        switch output.split(separator: "\n").first?.trimmingCharacters(in: .whitespaces) {
        case "Connected": return .connected
        case "Connecting": return .connecting
        case "Disconnected": return .disconnected
        case "Disconnecting": return .disconnecting
        case "Reasserting": return .reasserting
        default: return .unknown
        }
    }
}

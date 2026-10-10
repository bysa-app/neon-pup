import Foundation
import AppKit
import SystemConfiguration

/// Neon Pup and another VPN app must never run at the same time (the maintainer uses Clash Verge on his Mac):
/// two apps fighting over the network can leave traffic outside the tunnel.
public enum OtherVPNDetector {
    /// The name to show, or nil when nothing else is in the way.
    public static func activeName() -> String? {
        if let settings = SCDynamicStoreCopyProxies(nil) as? [String: Any] {
            for key in ["HTTPEnable", "HTTPSEnable", "SOCKSEnable"] where (settings[key] as? Int) == 1 {
                return clashRunning() ? "Clash" : "Another proxy app"
            }
        }
        if clashRunning() && clashCaptureAllOn() { return "Clash" }
        // Any other VPN (NordVPN, Tailscale, WireGuard, another sing-box) shows up as a tunnel carrying
        // the internet route before Neon Pup starts (final review #13).
        if let interface = routeInterface(), interface.hasPrefix("utun") { return "Another VPN app" }
        return nil
    }

    static func routeInterface() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/sbin/route")
        p.arguments = ["-n", "get", "1.1.1.1"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        return out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("interface: ") }?.replacingOccurrences(of: "interface: ", with: "")
    }

    static func clashRunning() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-x", "verge-mihomo"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    static func clashCaptureAllOn() -> Bool {
        let path = NSHomeDirectory() + "/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/verge.yaml"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
        return text.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == "enable_tun_mode: true" }
    }

    /// Plain http on purpose: hotel networks intercept it and redirect to their login page.
    public static func openLoginPage() {
        if let url = URL(string: "http://captive.apple.com") { NSWorkspace.shared.open(url) }
    }
}

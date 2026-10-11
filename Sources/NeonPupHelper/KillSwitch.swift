import Foundation
import Darwin
import NeonPupCore

/// The kill switch, as seen by the root helper. "Wanted" is remembered on disk (survives helper
/// restarts, and China mode after a reboot once the app reconnects). The Mac is sealed whenever the
/// kill switch is wanted and the engine is not running; while the engine runs the tunnel's strict
/// routing captures everything, so the seal is lifted. Rules go under the system's own "com.apple/*"
/// anchor point (no edits to /etc/pf.conf) and pf is enabled with a reference token. The rules and pf's
/// enabled state do not survive a reboot, but "wanted" and the token file do: the helper starts at boot
/// (RunAtLoad) and re-seals in China mode, and seal() always re-checks that pf is really enabled
/// (final review #1: a stale token file made seal() skip enabling pf after a reboot).
final class KillSwitch {
    static let anchor = "com.apple/co.holinic.neonpup"
    private var rulesFile: URL { HelperPaths.state.appendingPathComponent("killswitch.conf") }
    private var tokenFile: URL { HelperPaths.state.appendingPathComponent("pf-token") }
    private var wantedFile: URL { HelperPaths.state.appendingPathComponent("killswitch-wanted") }
    private var chinaFile: URL { HelperPaths.state.appendingPathComponent("killswitch-china") }

    /// The block is wanted. The file records the boot it was written in (KillSwitchBootPolicy).
    var wanted: Bool {
        get { FileManager.default.fileExists(atPath: wantedFile.path) }
        set { setFlag(wantedFile, newValue, contents: KillSwitchBootPolicy.currentBoot() ?? "") }
    }

    /// China mode: the only case in which a block survives a restart.
    var chinaMode: Bool {
        get { FileManager.default.fileExists(atPath: chinaFile.path) }
        set { setFlag(chinaFile, newValue, contents: "china") }
    }

    /// Never deletes a flag that should stay (Codex boot review #2): an unchanged flag is left alone, a new one is
    /// written to a temporary file and renamed into place, so a crash leaves either the old or the new flag.
    private func setFlag(_ file: URL, _ on: Bool, contents: String) {
        guard (try? HelperPaths.ensureState()) != nil else { return }
        guard on else { try? FileManager.default.removeItem(at: file); return }
        let data = Data(contents.utf8)
        if (try? Data(contentsOf: file)) == data { return }
        let temp = file.deletingLastPathComponent().appendingPathComponent("." + file.lastPathComponent + ".new")
        try? FileManager.default.removeItem(at: temp)
        guard FileManager.default.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return }
        if rename(temp.path, file.path) != 0 { try? FileManager.default.removeItem(at: temp) }
    }

    /// At every helper launch: drop a block left by an earlier boot unless China mode is on (Codex review
    /// 2026-10-10: a power cut while connected sealed the Mac at the next boot with no app to lift it).
    func applyBootPolicy() {
        let recorded = try? String(contentsOf: wantedFile, encoding: .utf8)
        if !KillSwitchBootPolicy.keepAtLaunch(wanted: wanted, chinaMode: chinaMode, recordedBoot: recorded,
                                              currentBoot: KillSwitchBootPolicy.currentBoot()) {
            wanted = false
        }
    }

    static func tunnelNames() -> Set<String> {
        var names = Set<String>()
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let item = cursor {
            let name = String(cString: item.pointee.ifa_name)
            if name.hasPrefix("utun") { names.insert(name) }
            cursor = item.pointee.ifa_next
        }
        return names
    }

    /// True when every probe address, IPv4 and IPv6, routes into `name` (RouteCheck has the reasoning).
    static func tunnelCarriesDefaultRoute(_ name: String) -> Bool {
        let v4 = RouteCheck.v4Probes.map { route(["-n", "get", $0]) }
        guard RouteCheck.v4Carried(v4, tunnel: name) else { return false }
        let v6 = RouteCheck.v6Probes.map { route(["-n", "get", "-inet6", $0]) }
        return RouteCheck.v6CarriedOrAbsent(v6, tunnel: name)
    }

    /// stdout and stderr together: "not in table" arrives on stderr. A failure to run gives "".
    private static func route(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/sbin/route")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return "" }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        return out
    }

    /// Blocks everything but loopback and the local network, and forgets every open connection so
    /// nothing opened before keeps running outside the tunnel. nil = done.
    @discardableResult
    func seal() -> String? {
        do { try HelperPaths.ensureState() } catch { return "\(error)" }
        try? FileManager.default.removeItem(at: rulesFile)
        guard FileManager.default.createFile(atPath: rulesFile.path, contents: Data(KillSwitchRules.sealed.utf8),
                                             attributes: [.posixPermissions: 0o600]) else { return "could not write rules" }
        let load = pfctl(["-a", Self.anchor, "-f", rulesFile.path])
        guard load.status == 0 else { return "pf refused the rules: \(load.output.prefix(200))" }
        if !pfEnabled() {
            let on = pfctl(["-E"])
            if let token = on.output.split(separator: "\n").first(where: { $0.contains("Token") })?
                .split(separator: ":").last?.trimmingCharacters(in: .whitespaces), !token.isEmpty {
                try? FileManager.default.removeItem(at: tokenFile)
                FileManager.default.createFile(atPath: tokenFile.path, contents: Data(token.utf8),
                                               attributes: [.posixPermissions: 0o600])
            }
            guard pfEnabled() else { return "pf could not be enabled" }
        }
        // Drill 2026-10-10: a download started before the seal kept running on its remembered state.
        // A failed flush leaves those running, so it is a failure (Codex review #5).
        guard pfctl(["-F", "states"]).status == 0 || pfctl(["-F", "states"]).status == 0 else {
            return "pf could not drop open connections"
        }
        return nil
    }

    private func pfEnabled() -> Bool {
        pfctl(["-s", "info"]).output.contains("Status: Enabled")
    }

    /// nil = lifted. A failure is reported, never swallowed (Codex review #5): the Mac would stay blocked
    /// while the app says normal internet.
    @discardableResult
    func unseal() -> String? {
        let flush = pfctl(["-a", Self.anchor, "-F", "all"])
        let left = pfctl(["-a", Self.anchor, "-s", "rules"])
        guard flush.status == 0, left.status == 0,
              KillSwitchRules.anchorIsEmpty(left.output) else {
            return "could not lift the block: \(flush.output.prefix(200))"
        }
        // The token is released best effort: after a reboot it is stale and -X refuses it, which is harmless.
        if let token = try? String(contentsOf: tokenFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            _ = pfctl(["-X", token])
        }
        try? FileManager.default.removeItem(at: tokenFile)
        return nil
    }

    func report() -> String {
        ["== wanted: \(wanted)", "== pf info", pfctl(["-s", "info"]).output,
         "== main rules", pfctl(["-s", "rules"]).output,
         "== our rules (verbose)", pfctl(["-a", Self.anchor, "-s", "rules", "-v"]).output].joined(separator: "\n")
    }

    private func pfctl(_ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/sbin/pfctl")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

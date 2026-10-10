import Foundation
import NeonPupCore

/// Swaps a China time zone for Singapore while connected and puts the original back afterwards.
/// The original is recorded on disk so a crash or reboot can still restore it.
final class TimeZoneManager {
    private let record = HelperPaths.state.appendingPathComponent("timezone-restore.json")
    private struct Saved: Codable { let zone: String; let automatic: Bool }

    func currentZone() -> String {
        let link = (try? FileManager.default.destinationOfSymbolicLink(atPath: "/etc/localtime")) ?? ""
        return link.components(separatedBy: "zoneinfo/").last ?? TimeZone.current.identifier
    }

    private func automaticEnabled() -> Bool {
        run("/usr/bin/defaults", ["read", "/Library/Preferences/com.apple.timezone.auto", "Active"]).output
            .trimmingCharacters(in: .whitespacesAndNewlines) != "0"
    }

    func apply() -> String? {
        let zone = currentZone()
        guard let replacement = TimeZonePolicy.replacement(for: zone) else { return nil }
        if !FileManager.default.fileExists(atPath: record.path) {
            let saved = Saved(zone: zone, automatic: automaticEnabled())
            guard (try? HelperPaths.ensureState()) != nil else { return nil }
            FileManager.default.createFile(atPath: record.path, contents: try? JSONEncoder().encode(saved),
                                           attributes: [.posixPermissions: 0o600])
        }
        _ = run("/usr/bin/defaults", ["write", "/Library/Preferences/com.apple.timezone.auto", "Active", "-bool", "NO"])
        _ = run("/usr/sbin/systemsetup", ["-settimezone", replacement])
        return replacement
    }

    func restore() {
        guard let data = try? Data(contentsOf: record),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        _ = run("/usr/sbin/systemsetup", ["-settimezone", saved.zone])
        _ = run("/usr/bin/defaults", ["write", "/Library/Preferences/com.apple.timezone.auto", "Active",
                                       "-bool", saved.automatic ? "YES" : "NO"])
        try? FileManager.default.removeItem(at: record)
    }

    @discardableResult
    private func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "\(error)") }
        p.waitUntilExit()
        return (p.terminationStatus, String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
    }
}

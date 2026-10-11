import Foundation
import AppKit
import Security
import NeonPupCore

/// Everything Neon Pup does with SFM, through public macOS interfaces only (no edits to SFM's own data, no
/// clicking for the user): check it, start and stop its VPN, open it, hand it the profile link.
public final class SFMBridge: @unchecked Sendable {
    public typealias Runner = (_ path: String, _ args: [String]) -> String
    private let run: Runner

    public init(run: @escaping Runner = SFMBridge.runCommand) { self.run = run }

    /// SFM is in Applications and signed by SFM's own team (never trust whatever answers to sing-box://).
    public func appTrusted() -> Bool {
        let url = URL(fileURLWithPath: SFMStatus.appPath) as CFURL
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(url, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(SFMStatus.appRequirement as CFString, [], &requirement) == errSecSuccess
        else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement) == errSecSuccess
    }

    public func installedVersion() -> String? {
        let plist = URL(fileURLWithPath: SFMStatus.appPath + "/Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: plist) else { return nil }
        return dict["CFBundleShortVersionString"] as? String
    }

    public func extensionState() -> SFMStatus.ExtensionState {
        SFMStatus.extensionState(run("/usr/bin/systemextensionsctl", ["list"]))
    }

    public func serviceID() -> String? { SFMStatus.vpnService(run("/usr/sbin/scutil", ["--nc", "list"])) }

    public func connection() -> SFMStatus.Connection {
        guard let id = serviceID() else { return .unknown }
        return SFMStatus.connection(run("/usr/sbin/scutil", ["--nc", "status", id]))
    }

    public func start() {
        guard let id = serviceID() else { return }
        _ = run("/usr/sbin/scutil", ["--nc", "start", id])
    }

    public func stop() {
        guard let id = serviceID() else { return }
        _ = run("/usr/sbin/scutil", ["--nc", "stop", id])
    }

    public func openApp() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: SFMStatus.appPath), configuration: .init(), completionHandler: nil)
    }

    /// Opens the import link in the verified SFM app itself.
    public func openImport(profileURL: URL, name: String = "Neon Pup") {
        let encoded = profileURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let nameEncoded = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "Neon%20Pup"
        guard appTrusted(), let link = URL(string: "sing-box://import-remote-profile?url=\(encoded)#\(nameEncoded)") else { return }
        NSWorkspace.shared.open([link], withApplicationAt: URL(fileURLWithPath: SFMStatus.appPath), configuration: .init(), completionHandler: nil)
    }

    // MARK: Wi-Fi (China mode "Go offline": really offline, no firewall tricks)

    public func wifiDevice() -> String? {
        let out = run("/usr/sbin/networksetup", ["-listallhardwareports"])
        let lines = out.split(separator: "\n").map(String.init)
        for (i, line) in lines.enumerated() where line.hasSuffix("Wi-Fi") && i + 1 < lines.count {
            return lines[i + 1].replacingOccurrences(of: "Device: ", with: "").trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// true only when the hardware list was read and has no Wi-Fi port (a failed read is not "no Wi-Fi").
    public func hasNoWifi() -> Bool {
        let out = run("/usr/sbin/networksetup", ["-listallhardwareports"])
        return out.contains("Hardware Port:") && wifiDevice() == nil
    }

    /// nil = couldn't tell.
    public func wifiPower() -> Bool? {
        guard let dev = wifiDevice() else { return nil }
        let out = run("/usr/sbin/networksetup", ["-getairportpower", dev])
        if out.contains(": On") { return true }
        if out.contains(": Off") { return false }
        return nil
    }

    /// Unknown counts as on: Neon Pup never claims offline without seeing it.
    public func wifiIsOn() -> Bool { wifiPower() ?? true }

    /// true when Wi-Fi really is in the asked state afterwards (read back, a few tries).
    @discardableResult
    public func setWifi(_ on: Bool) -> Bool {
        guard let dev = wifiDevice() else { return false }
        for _ in 0..<3 {
            _ = run("/usr/sbin/networksetup", ["-setairportpower", dev, on ? "on" : "off"])
            if wifiPower() == on { return true }
            usleep(300_000)
        }
        return false
    }

    public static func runCommand(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return "" }
        // Never hang the app on a stuck system tool: give up after 10 seconds.
        let deadline = DispatchTime.now() + 10
        DispatchQueue.global().asyncAfter(deadline: deadline) {
            guard p.isRunning else { return }
            p.terminate()
            // A tool that ignores the polite stop is killed 2 seconds later.
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { if p.isRunning { kill(p.processIdentifier, SIGKILL) } }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

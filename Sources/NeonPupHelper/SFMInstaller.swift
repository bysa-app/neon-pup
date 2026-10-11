import Foundation
import CryptoKit
import NeonPupCore

/// Installs the pinned SFM release for the first-run wizard (2026-10-10). Downloads only the pinned URL into
/// the helper's root-only folder, checks the SHA-256 and that the package is signed by SFM's team and
/// notarized, then runs Apple's installer. Never replaces an SFM the user already has in another version.
enum SFMInstaller {
    static func install() -> String? {
        let fm = FileManager.default
        if fm.fileExists(atPath: SFMStatus.appPath) {
            // Whatever sits at that path must really be SFM from its makers before setup moves on.
            guard appIsGenuine() else { return "the SFM app on this Mac is not signed by its makers" }
            let plist = NSDictionary(contentsOfFile: SFMStatus.appPath + "/Contents/Info.plist")
            let version = plist?["CFBundleShortVersionString"] as? String ?? "?"
            return version == SFMStatus.pinnedVersion ? nil
                : "SFM \(version) is already installed. Neon Pup is tested with \(SFMStatus.pinnedVersion)"
        }
        do { try HelperPaths.ensureState() } catch { return "could not prepare the download folder" }
        let pkg = HelperPaths.state.appendingPathComponent("SFM-\(SFMStatus.pinnedVersion).pkg")
        try? fm.removeItem(at: pkg)
        guard let url = URL(string: SFMStatus.packageURL), let data = download(url) else {
            return "could not download SFM. Check the internet connection and try again"
        }
        let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard hex == SFMStatus.packageSHA256 else { return "the SFM download did not match, so it was not installed" }
        guard fm.createFile(atPath: pkg.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            return "could not save the SFM download"
        }
        defer { try? fm.removeItem(at: pkg) }
        // The pinned hash already fixes the bytes; this is the second lock. pkgutil must succeed, and the
        // signer line itself (not any line) must name SFM's team.
        let (sigStatus, signature) = run("/usr/sbin/pkgutil", ["--check-signature", pkg.path])
        let signer = signature.split(separator: "\n").first { $0.contains("1. Developer ID Installer:") }
        guard sigStatus == 0, let signer, signer.hasSuffix("(\(SFMStatus.teamID))"),
              signature.contains("Notarization: trusted") else {
            return "the SFM package is not signed by its makers, so it was not installed"
        }
        let (status, result) = run("/usr/sbin/installer", ["-pkg", pkg.path, "-target", "/"])
        guard status == 0, fm.fileExists(atPath: SFMStatus.appPath) else {
            return "SFM did not install: \(result.suffix(200))"
        }
        guard appIsGenuine() else { return "the installed SFM app is not signed by its makers" }
        return nil
    }

    /// codesign checks the app against SFM's team and bundle id (the same requirement the app uses).
    static func appIsGenuine() -> Bool {
        run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R=\(SFMStatus.appRequirement)",
                                  SFMStatus.appPath]).0 == 0
    }

    private static func download(_ url: URL) -> Data? {
        let done = DispatchSemaphore(value: 0)
        var result: Data?
        let task = URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 120)) { data, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200 { result = data }
            done.signal()
        }
        task.resume()
        _ = done.wait(timeout: .now() + 300)
        return result
    }

    private static func run(_ path: String, _ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

/// Ends the hotel window from the helper, so it closes even if the app crashed or quit (Codex reviews
/// 2026-10-10). Only a local engine port and the two normal modes are accepted. While an expiry is pending the
/// helper does not exit; the switch back is retried until the engine confirms it.
final class HotelExpiry {
    private var generation = 0
    private let lock = NSLock()
    private(set) var pending = false
    /// Called after the expiry finished or was cancelled (lets the helper exit when idle).
    var onSettled: () -> Void = {}

    /// true = armed. The app opens the hotel window only after this.
    func arm(seconds: Int, apiPort: Int, secret: String, mode: String) -> Bool {
        guard (1...900).contains(seconds), (1024...65535).contains(apiPort), ["Rule", "Global"].contains(mode),
              !secret.isEmpty, secret.count < 200, secret.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
        else { return false }
        lock.lock(); generation += 1; let mine = generation; pending = true; lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(seconds)) { [weak self] in
            self?.fire(mine, attempt: 1, apiPort: apiPort, secret: secret, mode: mode)
        }
        return true
    }

    func cancel() {
        lock.lock(); generation += 1; pending = false; lock.unlock()
        onSettled()
    }

    private func fire(_ mine: Int, attempt: Int, apiPort: Int, secret: String, mode: String) {
        lock.lock(); let current = generation == mine; lock.unlock()
        guard current, let url = URL(string: "http://127.0.0.1:\(apiPort)/configs") else { return }
        var req = URLRequest(url: url, timeoutInterval: 5)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["mode": mode])
        URLSession.shared.dataTask(with: req) { [weak self] _, response, _ in
            guard let self else { return }
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            // Engine gone (tunnel stopped) also ends it: there is no Direct mode without an engine.
            let engineGone = response == nil && attempt >= 3
            if ok || engineGone || attempt >= 10 {
                self.lock.lock(); if self.generation == mine { self.pending = false }; self.lock.unlock()
                self.onSettled()
            } else {
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                    self.fire(mine, attempt: attempt + 1, apiPort: apiPort, secret: secret, mode: mode)
                }
            }
        }.resume()
    }
}

import Foundation
import Darwin
import NeonPupCore

/// Runs sing-box as root. Restarts it once after an unexpected exit, then gives up.
final class EngineSupervisor {
    private let queue = DispatchQueue(label: "co.holinic.neonpup.engine")
    private var process: Process?
    private var output: Pipe?
    let killSwitch = KillSwitch()
    private var stopping = false
    private var restarts = 0
    private var lastError: String?
    let stateDir = HelperPaths.state
    /// The engine's recent output, for "Copy a report" (2026-10-10). Memory only, never written to disk.
    private var log = LogRing()

    /// The app bundle the helper was launched from (user-writable when it sits in /Applications).
    private var appBundle: URL {
        // launchd starts BundleProgram with a relative argv[0], so ask the kernel for the real path.
        Self.executablePath().resolvingSymlinksInPath()
            .deletingLastPathComponent()            // MacOS
            .deletingLastPathComponent()            // Contents
            .deletingLastPathComponent()            // Neon Pup.app
    }

    static func executablePath() -> URL {
        var buffer = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN))
        let length = proc_pidpath(getpid(), &buffer, UInt32(buffer.count))
        return length > 0 ? URL(fileURLWithPath: String(cString: buffer)) : URL(fileURLWithPath: CommandLine.arguments[0])
    }

    /// Root-owned copy of the whole app; only its contents are ever executed or read as root.
    private var stagedApp: URL { stateDir.appendingPathComponent("app/Neon Pup.app", isDirectory: true) }
    private var stagedResources: URL { stagedApp.appendingPathComponent("Contents/Resources") }
    private var stagedEngine: URL { stagedResources.appendingPathComponent("sing-box") }

    /// Copies the app into the root-only folder, then verifies the copy's complete signature
    /// (code, sing-box, lists, settings). Checking the copy closes the swap-after-check gap.
    private func stageLocked() throws {
        let fm = FileManager.default
        try HelperPaths.ensureState()
        let parent = stagedApp.deletingLastPathComponent()
        try? fm.removeItem(at: parent)
        try fm.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try fm.copyItem(at: appBundle, to: stagedApp)
        guard AppBundleTrust.isSignedByUs(bundle: stagedApp) else {
            try? fm.removeItem(at: parent)
            throw HelperError("Neon Pup's signature does not check out, refusing to run")
        }
        // No downgrade: never run an older signed version than this Mac has already run.
        let info = NSDictionary(contentsOf: stagedApp.appendingPathComponent("Contents/Info.plist"))
        let version = info?["CFBundleVersion"] as? String ?? ""
        let floorFile = stateDir.appendingPathComponent("min-version")
        let floor = (try? String(contentsOf: floorFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard VersionFloor.allows(version, floor: floor) else {
            try? fm.removeItem(at: parent)
            throw HelperError("this Neon Pup is older than one already used here, please install the newest one")
        }
        try? fm.removeItem(at: floorFile)
        fm.createFile(atPath: floorFile.path, contents: Data(version.utf8), attributes: [.posixPermissions: 0o600])
    }

    /// Builds the settings from the verified copy, starts the engine and returns how to reach it.
    func start(roads: Data) -> (Int, String?, String?) {
        queue.sync {
            stopLocked()
            do {
                try stageLocked()
                // Own roads: the app sends only checked road fields; the helper decodes them into strict
                // types and ConfigTemplate validates every field again before building the settings.
                guard let specs = try? JSONDecoder().decode([RoadSpec].self, from: roads) else {
                    throw HelperError("the roads could not be read")
                }
                let access = EngineAccess(port: FreePort.find(), secret: UUID().uuidString)
                let config: Data
                do {
                    config = try ConfigTemplate.build(roads: specs, options: RuntimeOptions(
                        resourcesPath: stagedResources.path, apiPort: access.port, apiSecret: access.secret))
                } catch ConfigTemplateError.noRoads {
                    throw HelperError("add your roads first")
                } catch ConfigTemplateError.tooManyRoads {
                    throw HelperError("only \(RoadValidator.maxRoads) roads fit")
                } catch ConfigTemplateError.invalidRoad(let index, let problems) {
                    throw HelperError("road \(index + 1) has a problem with: " + problems.joined(separator: ", "))
                }
                let file = stateDir.appendingPathComponent("config.json")
                try? FileManager.default.removeItem(at: file)
                guard FileManager.default.createFile(atPath: file.path, contents: config,
                                                     attributes: [.posixPermissions: 0o600]) else {
                    throw HelperError("could not write settings")
                }
                let check = Process()
                check.executableURL = stagedEngine
                check.arguments = ["check", "-c", file.path]
                let pipe = Pipe()
                check.standardOutput = pipe
                check.standardError = pipe
                try check.run()
                check.waitUntilExit()
                if check.terminationStatus != 0 {
                    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    throw HelperError(LogLine.lastError(in: out) ?? "settings check failed")
                }
                stopping = false
                restarts = 0
                lastError = nil
                try launchSealedLocked(file)
                return (access.port, access.secret, nil)
            } catch let error as HelperError {
                lastError = error.message
                return (0, nil, lastError)
            } catch {
                lastError = "\(error)"
                return (0, nil, lastError)
            }
        }
    }

    /// Seal while the engine starts, launch it, and lift the seal only once the engine's own tunnel is
    /// confirmed to carry the default route. If that never happens the Mac stays sealed (fail-closed);
    /// the app's next kill switch sync retries.
    private func launchSealedLocked(_ file: URL) throws {
        sealIfWantedLocked()
        try launchLocked(file)
        unsealIfTunnelLocked(waitSeconds: 6)
    }

    private func unsealIfTunnelLocked(waitSeconds: Int) {
        guard killSwitch.wanted else { return }
        for _ in 0..<(waitSeconds * 10) {
            if process?.isRunning == true, KillSwitch.tunnelCarriesDefaultRoute(ConfigTemplate.tunnelName) {
                if let error = killSwitch.unseal() { lastError = error }
                return
            }
            usleep(100_000)
        }
        lastError = "the tunnel did not come up, keeping everything blocked"
    }

    private func launchLocked(_ file: URL) throws {
        let p = Process()
        p.executableURL = stagedEngine
        p.arguments = ["run", "-c", file.path, "-D", stateDir.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            // EOF: without clearing the handler Foundation keeps calling it and spins a core (final review I-3).
            if data.isEmpty { handle.readabilityHandler = nil; return }
            guard let text = String(data: data, encoding: .utf8) else { return }
            let line = LogLine.lastError(in: text)
            self?.queue.async {
                self?.log.append(text)
                if let line { self?.lastError = line }
            }
        }
        p.terminationHandler = { [weak self] proc in
            self?.queue.async { self?.handleExit(proc, file) }
        }
        try p.run()
        process = p
        output = pipe
        // Recorded so a fresh helper can stop an engine left behind by a helper that died (final review I-5).
        let pidFile = stateDir.appendingPathComponent("engine.pid")
        try? FileManager.default.removeItem(at: pidFile)
        FileManager.default.createFile(atPath: pidFile.path, contents: Data("\(p.processIdentifier)".utf8),
                                       attributes: [.posixPermissions: 0o600])
    }

    /// Stops an engine recorded in engine.pid that this helper does not supervise, but only if that pid
    /// really is the staged sing-box (pids get reused).
    func stopOrphan() {
        let pidFile = stateDir.appendingPathComponent("engine.pid")
        defer { try? FileManager.default.removeItem(at: pidFile) }
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 1,
              pid != process?.processIdentifier else { return }
        var buffer = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0,
              String(cString: buffer) == stagedEngine.path else { return }
        kill(pid, SIGTERM)
        for _ in 0..<30 where kill(pid, 0) == 0 { usleep(100_000) }
        if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
    }

    private func handleExit(_ proc: Process, _ file: URL) {
        guard proc === process else { return }
        process = nil
        // Seal at once (milliseconds, not the app's next check): a dead tunnel must not leak.
        sealIfWantedLocked()
        guard !stopping else { return }
        if restarts < 1 {
            restarts += 1
            try? launchSealedLocked(file)
        } else if lastError == nil {
            lastError = "the engine stopped twice"
        }
    }

    func stop() { queue.sync { stopLocked() } }

    private func stopLocked() {
        stopping = true
        if let p = process, p.isRunning {
            p.terminate()
            // sing-box can hang tearing down the TUN; never wait forever (final review I-4).
            for _ in 0..<30 where p.isRunning { usleep(100_000) }
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
            p.waitUntilExit()
        }
        output?.fileHandleForReading.readabilityHandler = nil
        output = nil
        process = nil
        stopOrphan()
        sealIfWantedLocked()
    }

    /// Seal, and make a failure visible: "paused" must never be shown when pf is not really blocking.
    private func sealIfWantedLocked() {
        guard killSwitch.wanted else { return }
        if let error = killSwitch.seal() { lastError = "could not pause the internet: \(error)" }
    }

    /// The app's wish. Sealed now only if the engine is not running; otherwise the tunnel covers it.
    func setKillSwitch(_ on: Bool) -> String? {
        queue.sync {
            killSwitch.wanted = on
            guard on else { return killSwitch.unseal() }
            // A flag that didn't save would only be lost if the helper restarted; block now as usual and record it
            // for the help report rather than claim the Mac isn't blocked (Codex boot review #2).
            if !killSwitch.wanted { lastError = "could not save the block for a helper restart" }
            guard process?.isRunning == true else { return killSwitch.seal() }
            // Engine running: stays sealed unless its own tunnel carries the default route.
            if !KillSwitch.tunnelCarriesDefaultRoute(ConfigTemplate.tunnelName), let error = killSwitch.seal() {
                return "could not pause the internet: \(error)"
            }
            unsealIfTunnelLocked(waitSeconds: 1)
            return nil
        }
    }

    func killSwitchReport() -> String { queue.sync { killSwitch.report() } }

    func setChinaMode(_ on: Bool) -> String? {
        queue.sync { killSwitch.chinaMode = on; return killSwitch.chinaMode == on ? nil : "could not save China mode" }
    }

    /// Helper launch: apply the boot policy before anything can seal.
    func applyBootPolicy() { queue.sync { killSwitch.applyBootPolicy() } }

    func recentLog() -> String { queue.sync { log.text } }

    func status() -> (Bool, String?) {
        queue.sync { (process?.isRunning ?? false, lastError) }
    }
}

struct HelperError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// Root-only state folder. /private/var/db is root:wheel 755, so unlike /Library/Application Support
/// no admin user can plant a symlink here (security review 2026-10-09).
enum HelperPaths {
    static let state = URL(fileURLWithPath: "/private/var/db/co.holinic.neonpup", isDirectory: true)

    // Deliberately no cleanup of the pre-2026-10-09 folder in /Library/Application Support: a root
    // recursive delete inside an admin-writable folder can be redirected by a swapped symlink.
    static func ensureState() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: state.path) {
            try fm.createDirectory(at: state, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        }
        guard SafeFolder.isRootOwnedRealFolder(state.path) else {
            throw HelperError("Neon Pup's private folder is not safe, refusing to run")
        }
    }
}

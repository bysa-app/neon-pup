import Foundation
import NeonPupCore

@MainActor
public final class AppModel: ObservableObject {
    @Published public private(set) var phase: Phase = .off
    @Published public private(set) var mode: RoadMode
    @Published public private(set) var pickedRoad: String?
    @Published public private(set) var delays: [String: Int] = [:]
    /// The person's roads, in their order (Keychain). Claude uses the first one that works.
    @Published public private(set) var roadSpecs: [RoadSpec]
    public var roads: [Road] { Roads.from(roadSpecs) }
    private var order: [String] { roads.map(\.tag) }
    /// Kill switch stays on even while napping (the maintainer 2026-10-10). Off by default.
    @Published public private(set) var chinaMode: Bool
    public private(set) var lastError: String?
    public var isOn: Bool { AppStateMachine.isOn(phase) }
    /// Quit must clean up whenever something may still be running or blocking: connected, "paused",
    /// or a seal that failed (Codex review #7: quitting from "paused" left the Mac blocked).
    public var needsStopOnQuit: Bool { isOn || engine != nil || phase == .failed || phase == .trouble(.notSealed) }

    enum Keys {
        static let mode = "roadMode", road = "pickedRoad", port = "engineAPIPort", secret = "engineAPISecret"
        static let chinaMode = "chinaMode"
    }

    private let helper: HelperControlling
    private let makeEngine: (Int, String) -> EngineControlling
    private let probe: DirectProbing
    private let defaults: UserDefaults
    private let store: RoadStore
    private let pause: (UInt64) async -> Void
    private let notify: (String) -> Void
    private let monitorEnabled: Bool
    private var engine: EngineControlling?
    /// What each selector ("choice", "claude") was last pointed at, to avoid needless switches.
    private var selections: [String: String] = [:]
    private let otherVPN: () -> String?
    private let openLoginPage: () -> Void
    private var hotelLoginTimer: Task<Void, Never>?
    private let hotelLoginNanos: UInt64 = 300_000_000_000
    private let hotelPollNanos: UInt64 = 3_000_000_000
    private var monitor: Task<Void, Never>?
    private var notifiedAllDown = false
    private var busy = false
    /// Bumped by wake, nap and quit. Work that resumes after an await in an older generation stops,
    /// so a tap during "Sniffing for a road..." cannot leave the Mac changed (final review I-1).
    private var generation = 0
    private var checking = false
    /// Roads were saved while a connect was in progress: reconnect with them once it finishes.
    private var roadsChangedDuringConnect = false
    private var checkAgain = false
    private let connectAttempts = 20
    private let monitorInterval: UInt64 = 15_000_000_000

    public init(helper: HelperControlling,
                makeEngine: @escaping (Int, String) -> EngineControlling = { EngineAPI(port: $0, secret: $1) },
                probe: DirectProbing = DirectProbe(),
                defaults: UserDefaults = .standard,
                store: RoadStore,
                pause: @escaping (UInt64) async -> Void = { try? await Task.sleep(nanoseconds: $0) },
                notify: @escaping (String) -> Void = { _ in },
                monitorEnabled: Bool = true,
                otherVPN: @escaping () -> String? = OtherVPNDetector.activeName,
                openLoginPage: @escaping () -> Void = OtherVPNDetector.openLoginPage) {
        self.helper = helper; self.makeEngine = makeEngine; self.probe = probe; self.defaults = defaults
        self.store = store; self.pause = pause; self.notify = notify
        self.monitorEnabled = monitorEnabled; self.otherVPN = otherVPN; self.openLoginPage = openLoginPage
        self.mode = RoadMode(stored: defaults.string(forKey: Keys.mode))
        self.chinaMode = defaults.bool(forKey: Keys.chinaMode)
        self.roadSpecs = store.load()
        self.pickedRoad = defaults.string(forKey: Keys.road)
    }

    private func send(_ event: Event) { phase = AppStateMachine.reduce(phase, event) }

    /// On while connected, while a dead engine left her "paused", after a failed seal (keep trying, never
    /// lift it by itself; security review), and always in China mode.
    private var killSwitchWanted: Bool { chinaMode || isOn || phase == .failed || phase == .trouble(.notSealed) }

    @discardableResult
    private func syncKillSwitch() async -> String? { await helper.setKillSwitch(killSwitchWanted) }

    /// Like syncKillSwitch, but a failed seal that was needed becomes visible instead of silent.
    private func enforceKillSwitch() async {
        if let error = await syncKillSwitch(), killSwitchWanted {
            lastError = error
            send(.sealFailed)
        } else if phase == .trouble(.notSealed) {
            // The retry worked. With the engine still running the tunnel carries everything again (the next
            // check confirms it); without it the Mac is blocked, which is the "paused" state (Codex review #1).
            phase = engine != nil ? .connecting : .failed
        }
    }

    /// On launch: take over an engine left running by a crashed app, otherwise make sure nothing is left changed.
    public func reattach() async {
        let readiness = helper.readiness()
        guard readiness == .ready else {
            // China mode cannot be enforced without the helper: say so (approval reset by an OS update, or
            // the helper could not be reached or replaced).
            if chinaMode { phase = readiness == .needsApproval ? .trouble(.needsApproval) : .trouble(.notSealed) }
            if case .error(let message) = readiness { lastError = message }
            return
        }
        let status = await helper.status()
        if status.running, let secret = defaults.string(forKey: Keys.secret), defaults.object(forKey: Keys.port) != nil {
            engine = makeEngine(defaults.integer(forKey: Keys.port), secret)
            selections = [:]
            phase = .connecting
            // A crash during the hotel window leaves the engine in Direct; close it, or restart the engine
            // (a new one starts in Rule) when it will not switch (Codex review #2).
            if let engine, await !engine.setMode("Rule") {
                await reconnect()
                return
            }
            await syncKillSwitch()
            await check()
            startMonitor()
        } else {
            if status.running { await helper.stop() }
            await helper.restoreTimeZone()
            phase = .off
            // A crash can leave the kill switch on; outside China mode, being off means normal internet.
            await enforceKillSwitch()
        }
    }

    public func wake() async {
        await wakeOnce()
        while roadsChangedDuringConnect {
            roadsChangedDuringConnect = false
            if isOn { await reconnect() }
        }
    }

    /// Restart the engine on the current roads WITHOUT lifting the kill switch in between (Codex review:
    /// going through nap() left a few seconds of ordinary routing). Stopping makes the helper seal.
    private func reconnect() async {
        repeat {
            // A save during this reconnect's own connect is picked up here, not left for a later wake.
            roadsChangedDuringConnect = false
            generation += 1
            let mine = generation
            monitor?.cancel()
            monitor = nil
            hotelLoginTimer?.cancel()
            hotelLoginTimer = nil
            await helper.stop()
            // She napped while the engine stopped: her tap wins (Codex review #6).
            guard generation == mine else { return }
            engine = nil
            selections = [:]
            phase = .off
            await wakeOnce()
        } while roadsChangedDuringConnect
        // If the reconnect could not start (no roads, another VPN app...), the helper sealed when it
        // stopped; bring the kill switch in line with what the panel now shows (security review).
        if !isOn {
            // No roads left, another VPN app...: nothing runs, so the time zone goes back (Codex review #8).
            await helper.restoreTimeZone()
            await enforceKillSwitch()
        }
    }

    private func wakeOnce() async {
        guard !isOn, !busy else { return }
        busy = true
        defer { busy = false }
        generation += 1
        let mine = generation
        send(.wakeTapped)
        guard !roadSpecs.isEmpty else {
            send(.noRoadsFound)
            return
        }
        if let other = otherVPN() {
            lastError = "\(other) is on"
            send(.otherVPNFound)
            return
        }
        switch helper.readiness() {
        case .needsApproval:
            send(.helperNeedsApproval)
            helper.openApproval()
            return
        case .error(let message):
            lastError = message
            send(.engineFailed)
            return
        case .ready:
            break
        }
        // Block every way out except the tunnel before the engine starts, so nothing leaks while connecting.
        if let error = await helper.setKillSwitch(true) {
            lastError = error
            // The internet is NOT blocked, so never show "paused" here (Codex review #1).
            send(.sealFailed)
            return
        }
        guard generation == mine else { return }
        let access: EngineAccess
        let result = await helper.start(roads: roadSpecs)
        guard generation == mine else {
            // Napped while starting: make sure nothing stays running or changed.
            if case .started = result { await helper.stop() }
            await helper.restoreTimeZone()
            await syncKillSwitch()
            return
        }
        switch result {
        case .failed(let error):
            lastError = error
            send(.engineFailed)
            return
        case .started(let granted):
            access = granted
        }
        defaults.set(access.port, forKey: Keys.port)
        defaults.set(access.secret, forKey: Keys.secret)
        let eng = makeEngine(access.port, access.secret)
        engine = eng
        selections = [:]
        _ = await helper.applyTimeZone()
        guard generation == mine else { await helper.restoreTimeZone(); return }
        for _ in 0..<connectAttempts {
            if await eng.delay(of: "choice") != nil { break }
            guard generation == mine else { return }
            await pause(1_000_000_000)
        }
        guard generation == mine else { return }
        // The tunnel exists now: refresh the rules so they let it through.
        await syncKillSwitch()
        guard generation == mine else { return }
        await check()
        if generation == mine && isOn { startMonitor() }
    }

    public func nap() async {
        generation += 1
        monitor?.cancel()
        monitor = nil
        hotelLoginTimer?.cancel()
        hotelLoginTimer = nil
        // Outside China mode lift the kill switch first; otherwise stopping would seal and drop every
        // open connection for nothing (final review #11). In China mode stopping seals, as intended.
        let keepSealed = chinaMode
        if !keepSealed, let error = await helper.setKillSwitch(false) { lastError = error }
        await helper.stop()
        await helper.restoreTimeZone()
        engine = nil
        selections = [:]
        notifiedAllDown = false
        send(.napTapped)
        if keepSealed { await enforceKillSwitch() }
    }

    /// Quit, logout, shutdown: stop synchronously. Async work is not reliably scheduled while AppKit
    /// waits to terminate (Task 11 drill: quit hung with the engine still running).
    public func stopForQuit() {
        generation += 1
        monitor?.cancel()
        monitor = nil
        hotelLoginTimer?.cancel()
        helper.stopNow(keepKillSwitch: chinaMode)
        engine = nil
        selections = [:]
        send(.napTapped)
    }

    private func select(_ name: String, in group: String) async {
        guard let engine, selections[group] != name else { return }
        if await engine.select(name, in: group) { selections[group] = name }
    }

    /// Delay of every road, measured in parallel.
    private func measure(_ engine: EngineControlling) async -> [String: Int] {
        var result: [String: Int] = [:]
        await withTaskGroup(of: (String, Int?).self) { group in
            for tag in order { group.addTask { (tag, await engine.delay(of: tag)) } }
            for await (tag, delay) in group { if let delay { result[tag] = delay } }
        }
        return result
    }

    /// One check at a time; a request during a check runs once more afterwards (final review I-2).
    public func check() async {
        if checking { checkAgain = true; return }
        checking = true
        defer { checking = false }
        repeat {
            checkAgain = false
            await checkOnce()
        } while checkAgain && isOn
    }

    private func checkOnce() async {
        guard isOn, let engine else { return }
        let mine = generation
        // Re-confirm with the helper that the tunnel still carries the route; it seals at once if not.
        if let error = await syncKillSwitch() {
            guard generation == mine else { return }
            lastError = error
            send(.sealFailed)
            return
        }
        guard generation == mine else { return }
        let status = await helper.status()
        guard generation == mine else { return }
        if !status.running {
            lastError = status.lastError ?? lastError
            monitor?.cancel()
            hotelLoginTimer?.cancel()
            self.engine = nil
            await helper.restoreTimeZone()
            // The kill switch stays on: a dead tunnel must not open the direct way out. If the helper could
            // not seal, say so instead of "paused".
            let sealed = !(status.lastError ?? "").hasPrefix("could not pause the internet")
            send(sealed ? .engineFailed : .sealFailed)
            return
        }
        let alive = await measure(engine)
        guard generation == mine else { return }
        delays = alive
        // A picked road that was since deleted counts as no pick.
        let picked = pickedRoad.flatMap { order.contains($0) ? $0 : nil }
        guard let selection = RoadPolicy.selection(mode: mode, picked: picked, alive: Set(alive.keys), order: order) else {
            let direct = await probe.directInternetWorks()
            guard generation == mine else { return }
            send(.allRoadsDown(directInternet: direct))
            if direct, mode != .manual, !notifiedAllDown {
                notifiedAllDown = true
                notify("All servers are sleepy, I'll keep trying")
            }
            return
        }
        // During the hotel login window "choice" stays direct; Claude always follows the fixed order.
        if phase != .hotelLogin { await select(selection.choice, in: "choice") }
        await select(selection.claude, in: "claude")
        guard generation == mine else { return }
        notifiedAllDown = false
        send(selection.pickedRoadDown ? .pickedRoadUnreachable : .roadsBack)
    }

    private func startMonitor() {
        monitor?.cancel()
        guard monitorEnabled else { return }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.pause(self.monitorInterval)
                if Task.isCancelled { return }
                await self.check()
            }
        }
    }

    public func networkChanged() async {
        // Ask the helper to re-confirm the tunnel carries the route after the network changed.
        if killSwitchWanted { await enforceKillSwitch() }
        await check()
    }

    public func setChinaMode(_ on: Bool) async {
        chinaMode = on
        defaults.set(on, forKey: Keys.chinaMode)
        await enforceKillSwitch()
    }

    /// Opens ordinary web pages directly for up to 5 minutes so a hotel login page can load.
    /// Claude stays on its own roads the whole time, and name lookups never go direct.
    public func startHotelLogin() async {
        if !isOn { await wake() }
        guard isOn, engine != nil, phase != .hotelLogin else { return }
        send(.hotelLoginStarted)
        _ = await engine?.setMode("Direct")
        openLoginPage()
        hotelLoginTimer?.cancel()
        guard monitorEnabled else { return }
        hotelLoginTimer = Task { [weak self] in
            guard let self else { return }
            // Every few seconds: once a server answers she is logged in, so close the window early.
            for _ in 0..<(self.hotelLoginNanos / self.hotelPollNanos) {
                await self.pause(self.hotelPollNanos)
                if Task.isCancelled { return }
                await self.hotelLoginTick()
                if self.phase != .hotelLogin { return }
            }
            if !Task.isCancelled { await self.endHotelLogin() }
        }
    }

    /// Closes the login window as soon as any server answers (the maintainer 2026-10-10): the browser should use the
    /// local connection only for as long as the login takes.
    func hotelLoginTick() async {
        guard phase == .hotelLogin, let engine else { return }
        let alive = await measure(engine)
        guard phase == .hotelLogin, !alive.isEmpty else { return }
        await endHotelLogin()
    }

    public func endHotelLogin() async {
        guard phase == .hotelLogin else { return }
        hotelLoginTimer?.cancel()
        hotelLoginTimer = nil
        // Always close the direct window, whatever the roads do afterwards (final review #3). If the engine
        // refuses, restart it: a new engine starts in Rule (Codex review #3).
        let closed = await engine?.setMode("Rule") ?? true
        send(.hotelLoginEnded)
        guard closed else {
            await reconnect()
            return
        }
        await check()
    }

    public func setMode(_ newMode: RoadMode) async {
        mode = newMode
        defaults.set(newMode.rawValue, forKey: Keys.mode)
        guard isOn else { return }
        send(.roadPicked)
        await check()
    }

    public func pick(_ tag: String) async {
        pickedRoad = tag
        defaults.set(tag, forKey: Keys.road)
        mode = .manual
        defaults.set(RoadMode.manual.rawValue, forKey: Keys.mode)
        guard isOn else { return }
        send(.roadPicked)
        await check()
    }

    /// Replaces the roads (setup screen). Every road must pass the checks. While connected, reconnect so
    /// the engine and Claude's road follow the new list. Returns false when refused or not saved.
    @discardableResult
    public func setRoads(_ specs: [RoadSpec]) async -> Bool {
        guard specs.count <= RoadValidator.maxRoads, specs.allSatisfy({ RoadValidator.problems($0).isEmpty }),
              store.save(specs) else { return false }
        // A manual pick follows its road to the new position, or is cleared if that road was deleted.
        let pickedSpec = pickedRoad.flatMap { tag in roads.firstIndex { $0.tag == tag }.map { roadSpecs[$0] } }
        roadSpecs = specs
        delays = [:]
        if let spec = pickedSpec {
            // Matched on everything but the name, so a rename keeps the pick (Fable review #3).
            if let index = specs.firstIndex(where: { $0.sameRoad(as: spec) }) {
                pickedRoad = ConfigTemplate.tags(count: specs.count)[index]
                defaults.set(pickedRoad, forKey: Keys.road)
            } else {
                pickedRoad = nil
                defaults.removeObject(forKey: Keys.road)
            }
        }
        if busy {
            roadsChangedDuringConnect = true
        } else if isOn {
            await reconnect()
        } else if phase == .trouble(.noRoads), !specs.isEmpty {
            phase = .off
        }
        return true
    }

    public func refreshDelays() async {
        guard let engine else { delays = [:]; return }
        delays = await measure(engine)
    }

    public func helpReport(appVersion: String) async -> String {
        if engine != nil { await refreshDelays() }
        let info = ProcessInfo.processInfo.operatingSystemVersion
        var cpu = "intel"
        #if arch(arm64)
        cpu = "apple silicon"
        #endif
        let helperState: String
        switch helper.readiness() {
        case .ready: helperState = "ready"
        case .needsApproval: helperState = "needs approval"
        case .error(let e): helperState = "error: \(e)"
        }
        let facts = DiagnosticFacts(appVersion: appVersion,
                                    macOSVersion: "\(info.majorVersion).\(info.minorVersion).\(info.patchVersion)",
                                    cpu: cpu, phase: "\(phase)", mode: mode.rawValue + (chinaMode ? ", china mode" : ""), pickedRoad: pickedRoad,
                                    roadDelays: delays, lastError: lastError, helper: helperState)
        let log = helper.readiness() == .ready ? await helper.recentLog() : ""
        return Diagnostics.report(facts, roads: roads, log: log, redacting: Diagnostics.secrets(from: roadSpecs))
    }

    /// Gallery and previews only: a model frozen in a given state.
    public static func preview(phase: Phase, mode: RoadMode = .secure, pickedRoad: String? = nil, delays: [String: Int] = [:],
                               roads: [RoadSpec] = previewRoads) -> AppModel {
        let model = AppModel(helper: PreviewHelper(), store: InMemoryRoadStore(roads), monitorEnabled: false)
        model.phase = phase
        model.mode = mode
        model.pickedRoad = pickedRoad
        model.delays = delays
        return model
    }
}

/// Names only matter for previews; the values are format examples, not real servers.
public let previewRoads: [RoadSpec] = [
    RoadSpec(kind: .reality, name: "Singapore, everyday server", host: "192.0.2.1", port: 443,
             uuid: "00000000-0000-4000-8000-000000000000", serverName: "www.apple.com",
             publicKey: String(repeating: "A", count: 43), shortID: "", fingerprint: "chrome"),
    RoadSpec(kind: .hysteria2, name: "Singapore, turbo server", host: "192.0.2.1", port: 443, password: "preview",
             allowInsecure: true),
    RoadSpec(kind: .reality, name: "America, everyday server", host: "192.0.2.2", port: 443,
             uuid: "00000000-0000-4000-8000-000000000000", serverName: "www.apple.com",
             publicKey: String(repeating: "A", count: 43), shortID: "", fingerprint: "chrome"),
    RoadSpec(kind: .hysteria2, name: "America, turbo server", host: "192.0.2.2", port: 443, password: "preview"),
    RoadSpec(kind: .websocket, name: "Backup tunnel", host: "example.com", port: 443,
             uuid: "00000000-0000-4000-8000-000000000000", serverName: "example.com", path: "/"),
]

@MainActor
final class PreviewHelper: HelperControlling {
    func readiness() -> HelperReadiness { .ready }
    func openApproval() {}
    func start(roads: [RoadSpec]) async -> StartResult { .failed("preview") }
    func stop() async {}
    func status() async -> (running: Bool, lastError: String?) { (false, nil) }
    func applyTimeZone() async -> String? { nil }
    func restoreTimeZone() async {}
    func stopNow(keepKillSwitch: Bool) {}
    func setKillSwitch(_ on: Bool) async -> String? { nil }
    func recentLog() async -> String { "" }
}

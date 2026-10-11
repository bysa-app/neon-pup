import Foundation
import NeonPupCore

/// First-run setup for Neon Pup on SFM: one step at a time, each checked against the real system state so the
/// wizard ticks steps off by itself. Also keeps the profile SFM fetches in step with the user's servers.
@MainActor
public final class SFMSetup: ObservableObject {
    public enum Step: Int, CaseIterable, Sendable {
        case welcome, helper, install, systemExtension, servers, sendToSFM, addVPN, sfmSetting, firstStart, done
    }

    enum Keys {
        static let token = "sfmProfileToken", secret = "sfmAPISecret"
        static let fetched = "sfmProfileFetched", settingConfirmed = "sfmIncludeAllConfirmed"
        static let firstStart = "sfmFirstStartDone", welcomed = "sfmWelcomed"
    }

    public let bridge: SFMBridge
    public let server: ProfileServer
    public let secret: String
    private let defaults: UserDefaults
    private var helper: HelperControlling?
    @Published public internal(set) var step: Step = .welcome
    @Published public private(set) var working = false
    @Published public private(set) var problem: String?
    @Published public private(set) var fingerprint: String?

    public init(bridge: SFMBridge = SFMBridge(), defaults: UserDefaults = .standard) {
        self.bridge = bridge
        self.defaults = defaults
        func stored(_ key: String, _ make: () -> String) -> String {
            if let v = defaults.string(forKey: key), !v.isEmpty { return v }
            let v = make(); defaults.set(v, forKey: key); return v
        }
        let token = stored(Keys.token) { (0..<4).map { _ in String(format: "%08x", UInt32.random(in: .min ... .max)) }.joined() }
        secret = stored(Keys.secret) { UUID().uuidString }
        server = ProfileServer(port: SFMStatus.profilePort, token: token)
    }

    public func attach(helper: HelperControlling) { self.helper = helper }

    /// Serve the profile for these servers. Call at launch and whenever the server list changes.
    public func serve(roads: [RoadSpec]) {
        if let problem = server.start() { self.problem = problem }
        guard !roads.isEmpty else { fingerprint = nil; return }
        let options = RuntimeOptions(resourcesPath: "", apiPort: SFMStatus.apiPort, apiSecret: secret, platform: .sfm)
        if let data = try? ConfigTemplate.build(roads: roads, options: options) {
            server.update(data)
            fingerprint = ConfigTemplate.fingerprintTag(roads: roads)
        }
    }

    /// Every step that has a machine-checkable condition, in order; the first unmet one is the current step.
    public func refresh(hasRoads: Bool) {
        if server.lastSFMFetch != nil { defaults.set(true, forKey: Keys.fetched) }
        if bridge.connection() == .connected, bridge.serviceID() != nil { defaults.set(true, forKey: Keys.firstStart) }
        step = Self.firstUnmet(
            welcomed: defaults.bool(forKey: Keys.welcomed),
            helperReady: helper?.readiness() == .ready,
            installed: bridge.appTrusted() && bridge.installedVersion() == SFMStatus.pinnedVersion,
            extensionEnabled: bridge.extensionState() == .enabled,
            hasRoads: hasRoads,
            fetched: defaults.bool(forKey: Keys.fetched),
            vpnAdded: bridge.serviceID() != nil,
            settingConfirmed: defaults.bool(forKey: Keys.settingConfirmed),
            firstStart: defaults.bool(forKey: Keys.firstStart))
    }

    public var isComplete: Bool { step == .done }

    nonisolated static func firstUnmet(welcomed: Bool, helperReady: Bool, installed: Bool, extensionEnabled: Bool,
                                       hasRoads: Bool, fetched: Bool, vpnAdded: Bool, settingConfirmed: Bool,
                                       firstStart: Bool) -> Step {
        if !welcomed { return .welcome }
        if !helperReady { return .helper }
        if !installed { return .install }
        if !extensionEnabled { return .systemExtension }
        if !hasRoads { return .servers }
        if !fetched { return .sendToSFM }
        if !vpnAdded { return .addVPN }
        if !settingConfirmed { return .sfmSetting }
        if !firstStart { return .firstStart }
        return .done
    }

    // MARK: Actions behind the wizard's buttons

    public func finishWelcome() { defaults.set(true, forKey: Keys.welcomed) }
    public func confirmSFMSetting() { defaults.set(true, forKey: Keys.settingConfirmed) }
    public func openSFM() { bridge.openApp() }
    public func sendProfileToSFM() { bridge.openImport(profileURL: server.url) }

    public func installSFM() async {
        guard let helper else { return }
        working = true
        problem = await helper.installSFM()
        working = false
    }

    /// Lets the user run the setup again (e.g. after deleting SFM).
    public func restart() {
        for key in [Keys.welcomed, Keys.fetched, Keys.settingConfirmed, Keys.firstStart] { defaults.removeObject(forKey: key) }
    }
}

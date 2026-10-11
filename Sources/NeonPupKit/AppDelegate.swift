import AppKit
import SwiftUI
import Network
import UserNotifications
import NeonPupCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public let model: AppModel
    /// Neon Pup on SFM (2026-10-10): SFM's NetworkExtension tunnel underneath, set up by the first-run wizard.
    public let setup: SFMSetup
    private let pathMonitor = NWPathMonitor()
    private var serversWatch: Any?
    private var stepWatch: Any?

    private let host: SFMHost

    public override init() {
        let setup = SFMSetup()
        let helper = HelperClient()
        let host = SFMHost(base: helper, bridge: setup.bridge, secret: setup.secret)
        setup.attach(helper: helper)
        self.setup = setup
        self.host = host
        model = AppModel(helper: host,
                         store: KeychainRoadStore(),
                         notify: AppDelegate.notify,
                         // SFM's own tunnel is ours, not "another VPN app".
                         otherVPN: { setup.bridge.connection() == .connected ? nil : OtherVPNDetector.activeName() },
                         sfm: AppModel.SFMOptions(setupNeeded: { MainActor.assumeIsolated { !setup.isComplete } },
                                                  fingerprint: { MainActor.assumeIsolated { setup.fingerprint } }))
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Serve SFM its profile and keep it in step with the server list.
        setup.serve(roads: model.roadSpecs)
        serversWatch = model.$roadSpecs.sink { [weak self] roads in self?.setup.serve(roads: roads) }
        SetupWizardWindow.showFromPanel = { [weak self] in
            guard let self else { return }
            SetupWizardWindow.show(setup: self.setup, model: self.model)
        }
        Task {
            setup.refresh(hasRoads: !model.roadSpecs.isEmpty)
            // Setup finishing during this run: Neon Pup takes over the tunnel SFM's first start left running.
            // Only watched when setup was unfinished at launch (live test 2026-10-12: the step starts at
            // .welcome, so watching from the start stopped a running tunnel at every launch).
            if !setup.isComplete {
                stepWatch = setup.$step.removeDuplicates().dropFirst().sink { [weak self] step in
                    guard step == .done, let self else { return }
                    Task { await self.model.setupFinished() }
                }
            }
            // A Mac that ran the old engine may still carry its firewall block: lift it before anything else.
            if host.readiness() == .ready { await host.clearLegacyBlock() }
            await model.reattach()
            // First run, or setup not finished: open the setup wizard straight away.
            if !setup.isComplete { SetupWizardWindow.show(setup: setup, model: model) }
        }
        pathMonitor.pathUpdateHandler = { [weak self] _ in Task { @MainActor in await self?.model.networkChanged() } }
        pathMonitor.start(queue: .main)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.model.networkChanged() }
        }
    }

    private var panelWindow: NSWindow?

    /// Opening Neon Pup again (Finder, Spotlight, Launchpad) shows the panel as a normal window: on
    /// notched Macs with a full menu bar macOS hides the butterfly, and the user must still reach the button.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanelWindow()
        return false
    }

    public func showPanelWindow() {
        if panelWindow == nil {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Neon Pup"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PanelView(model: model, appVersion: version))
            window.center()
            panelWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        panelWindow?.makeKeyAndOrderFront(nil)
    }

    /// Quit, logout and shutdown all pass through here: put the Mac back to normal first.
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.needsStopOnQuit { model.stopForQuit() }
        return .terminateNow
    }

    static func notify(_ text: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Neon Pup"
            content.body = text
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}

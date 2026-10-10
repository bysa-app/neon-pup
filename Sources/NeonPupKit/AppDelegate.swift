import AppKit
import SwiftUI
import Network
import UserNotifications
import NeonPupCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public let model: AppModel
    private let pathMonitor = NWPathMonitor()

    public override init() {
        model = AppModel(helper: HelperClient(),
                         store: KeychainRoadStore(),
                         notify: AppDelegate.notify)
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            await model.reattach()
            // First run (or no roads saved): open the setup screen straight away.
            if model.roadSpecs.isEmpty { RoadsWindow.show(model: model) }
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

import SwiftUI
import AppKit
import NeonPupKit

struct NeonPupApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        MenuBarExtra {
            PanelView(model: delegate.model,
                      appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
        } label: {
            MenuBarIconLabel(delegate: delegate)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarIconLabel: View {
    @ObservedObject var model: AppModel
    init(delegate: AppDelegate) { model = delegate.model }
    var body: some View { MenuBarIcon(phase: model.phase) }
}

// No top-level `await` here: it would turn the whole program into one async task holding the main
// actor, and SwiftUI's app loop would then run inside it, so main-actor work (reattach, wake, quit
// cleanup) could never be scheduled. Found in the Task 11 quit drill: launch spun and quit hung.
let args = Array(CommandLine.arguments.dropFirst())
if args.first == "--spike" {
    Task { @MainActor in exit(await Spike.run(Array(args.dropFirst()))) }
    dispatchMain()
} else if args.first == "--render-gallery", args.count > 1 {
    Task { @MainActor in
        Gallery.render(to: URL(fileURLWithPath: args[1])).forEach { print($0.path) }
        exit(0)
    }
    dispatchMain()
} else {
    // New menu bar items appear at the far left of the icons, which on a notched Mac with a full menu bar
    // is hidden behind the notch or the app menus (the maintainer's Mac, 2026-10-09). Ask once for a spot next to
    // the clock; a position the user picks with Cmd-drag is stored under the same key and wins.
    let positionKey = "NSStatusItem Preferred Position Item-0"
    if UserDefaults.standard.object(forKey: positionKey) == nil {
        UserDefaults.standard.set(140.0, forKey: positionKey)
    }
    NeonPupApp.main()
}

import SwiftUI
import AppKit
import NeonPupCore

/// The words for each setup step (the maintainer 2026-10-10: no context needed, plain steps, no technical words).
public enum SetupCopy {
    public struct Page: Sendable {
        public let title: String
        public let intro: [String]
        public let steps: [String]
        public let waiting: String?
        /// Optional "why?" section, closed until opened (the maintainer 2026-10-12).
        public var why: (title: String, paragraphs: [String])? = nil
    }

    public static func page(_ step: SFMSetup.Step) -> Page {
        switch step {
        case .welcome:
            return Page(title: "Welcome to Neon Pup", intro: [
                "Neon Pup sends your Mac's internet through your own servers outside China, so blocked sites and Claude work. While it is connected, Claude only sees your server's location.",
                "It works together with a free app called SFM, made by the people behind the engine Neon Pup uses. SFM does its work in the background. You only use Neon Pup.",
                "Setup takes about 5 minutes and asks for your Mac password once or twice. Do it before you travel.",
            ], steps: [], waiting: nil)
        case .helper:
            return Page(title: "Allow Neon Pup", intro: [
                "Neon Pup needs a small helper to install SFM and to look after your time zone. macOS asks you to allow it once.",
            ], steps: [
                "Press Open System Settings.",
                "Under Allow in the Background, turn on Neon Pup.",
            ], waiting: "Neon Pup moves on as soon as it's allowed.")
        case .install:
            return Page(title: "Install SFM", intro: [
                "Neon Pup downloads SFM from the people who make it, checks it, and installs it. It's about 100 MB.",
            ], steps: ["Press Install SFM and wait."], waiting: nil, why: ("Why do I need SFM?", [
                "Neon Pup is the part you use: the button, your servers and the checks. SFM does the actual work of sending your internet through your servers.",
                "macOS only lets apps with a special Apple permission carry all of your Mac's internet, including the lookups that find each website. SFM has that permission. Without it, some lookups could go out directly in China, which breaks blocked sites and can show your real location.",
                "SFM is free and made by the people behind the engine Neon Pup uses. After setup you never need to open it.",
            ]))
        case .systemExtension:
            return Page(title: "Allow SFM to carry your internet", intro: [
                "macOS asks you to allow this once.",
            ], steps: [
                "Press Open SFM.",
                "If SFM asks about checking for updates, press \"No, thanks\". If it offers to install a helper service, press \"No, thanks\" again.",
                "In SFM, press Install System Extension.",
                "In System Settings, go to General, then Login Items & Extensions. Scroll down to Extensions and change the list from By App to By Category.",
                "Open Network Extensions, turn on SFMExtension, and confirm with your password or Touch ID.",
            ], waiting: "SFM is installed. Neon Pup moves on as soon as SFMExtension is on.")
        case .servers:
            return Page(title: "Add your servers", intro: [
                "Paste the server links you were given, or import the file you got. Whoever runs your servers gives you these.",
            ], steps: ["Press Open Your servers.", "Add your servers and press Save my servers."],
                        waiting: "Neon Pup moves on once your servers are saved.")
        case .sendToSFM:
            return Page(title: "Send your servers to SFM", intro: [], steps: [
                "Press Send to SFM.",
                "SFM asks \"Import remote profile Neon Pup?\". Press Import.",
                "SFM shows the profile. Press Create.",
            ], waiting: "Neon Pup moves on as soon as SFM has your servers.")
        case .addVPN:
            return Page(title: "Add the VPN to your Mac", intro: [], steps: [
                "Press Open SFM.",
                "In SFM, press Install Network Extension.",
                "macOS asks to add VPN configurations. Press Allow.",
            ], waiting: "Neon Pup moves on as soon as the VPN is added.")
        case .sfmSetting:
            return Page(title: "Turn on one SFM setting", intro: [
                "This keeps every app on your Mac inside the tunnel while it runs.",
            ], steps: [
                "Press Open SFM.",
                "In SFM, open Settings, then Packet Tunnel.",
                "Turn on includeAllNetworks.",
                "Come back here and press Done.",
            ], waiting: nil)
        case .firstStart:
            return Page(title: "Start SFM once", intro: [
                "SFM has to start once by itself. After that, Neon Pup starts and stops it for you.",
            ], steps: [
                "Press Open SFM.",
                "In SFM, press the play button at the top left.",
                "When a timer appears next to it, you're done. You can close SFM.",
            ], waiting: "Neon Pup moves on as soon as SFM is running.")
        case .done:
            return Page(title: "All set", intro: [
                "Click the butterfly in the menu bar and press Wake me up whenever you need it. You never need to open SFM again, but keep it installed.",
                "If SFM's window is still open, close it with the red X. That only closes the window: the connection keeps running in the background, and Neon Pup turns it on and off for you.",
            ], steps: [], waiting: nil)
        }
    }

    /// Shown on the last page and in the help guide.
    public static let goodToKnow = [
        "If you change your servers, Neon Pup asks you to open SFM and press its refresh button once. Until then it keeps using your old servers.",
        "If SFM offers an update, say no. Neon Pup is tested with the version it installed.",
        "Hotel or airport Wi-Fi with a login page: use Securely open public Wi-Fi login in Neon Pup.",
        "In China mode, Go offline turns Wi-Fi off. Wake me up turns it back on.",
        "Your phone needs its own app. Neon Pup is for this Mac only.",
    ]
}

struct SetupWizardView: View {
    @ObservedObject var setup: SFMSetup
    @ObservedObject var model: AppModel
    let close: () -> Void
    /// Gallery renders only: show the "why?" section opened.
    var whyOpen = false

    var body: some View {
        let page = SetupCopy.page(setup.step)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Set up Neon Pup").font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                Spacer()
                if setup.step != .welcome && setup.step != .done {
                    Text("Step \(setup.step.rawValue) of \(SFMSetup.Step.allCases.count - 2)")
                        .font(Theme.rounded(12)).foregroundStyle(Theme.textDim)
                }
            }
            Text(page.title).font(Theme.rounded(22, .bold)).foregroundStyle(Theme.pink)
            ForEach(Array(page.intro.enumerated()), id: \.offset) { item in
                Text(item.element).font(Theme.rounded(13)).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !page.steps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(page.steps.enumerated()), id: \.offset) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(item.offset + 1).").font(Theme.rounded(13, .bold)).foregroundStyle(Theme.teal)
                            Text(item.element).font(Theme.rounded(13)).foregroundStyle(Theme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.nightRaised))
            }
            if let why = page.why {
                Accordion(title: why.title, paragraphs: why.paragraphs, startsOpen: whyOpen)
            }
            if setup.step == .done {
                Text("Good to know").font(Theme.rounded(15, .bold)).foregroundStyle(Theme.teal)
                ForEach(Array(SetupCopy.goodToKnow.enumerated()), id: \.offset) { item in
                    Text(item.element).font(Theme.rounded(12)).foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let problem = setup.problem {
                Text(problem).font(Theme.rounded(12)).foregroundStyle(Theme.blush)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if setup.working {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Downloading and installing, please wait...").font(Theme.rounded(12)).foregroundStyle(Theme.text)
                }
            } else if let waiting = page.waiting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(waiting).font(Theme.rounded(12)).foregroundStyle(Theme.textDim)
                }
            }
            actions
        }
        .padding(22)
        .frame(width: 440)
        .background(Theme.night)
        .task {
            // Re-check every two seconds, so each step ticks off by itself.
            while !Task.isCancelled {
                setup.refresh(hasRoads: !model.roadSpecs.isEmpty)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        switch setup.step {
        case .welcome:
            GlowButton(title: "Start", wakes: true) { setup.finishWelcome(); setup.refresh(hasRoads: !model.roadSpecs.isEmpty) }
        case .helper:
            GlowButton(title: "Open System Settings", wakes: true) { model.openHelperApproval() }
        case .install:
            GlowButton(title: setup.working ? "Installing..." : "Install SFM", wakes: true) {
                Task { await setup.installSFM(); setup.refresh(hasRoads: !model.roadSpecs.isEmpty) }
            }.disabled(setup.working)
        case .systemExtension, .addVPN, .firstStart:
            GlowButton(title: "Open SFM", wakes: true) { setup.openSFM() }
        case .servers:
            GlowButton(title: "Open Your servers", wakes: true) { RoadsWindow.show(model: model) }
        case .sendToSFM:
            GlowButton(title: "Send to SFM", wakes: true) { setup.sendProfileToSFM() }
        case .sfmSetting:
            HStack(spacing: 12) {
                TextLink(title: "Open SFM") { setup.openSFM() }
                Spacer()
                GlowButton(title: "Done", wakes: true) { setup.confirmSFMSetting(); setup.refresh(hasRoads: !model.roadSpecs.isEmpty) }
            }
        case .done:
            GlowButton(title: "Finish", wakes: true) { close() }
        }
    }
}

@MainActor
public enum SetupWizardWindow {
    private static var window: NSWindow?
    /// Set by the app delegate so the panel can reopen setup without owning it.
    public static var showFromPanel: () -> Void = {}

    public static func show(setup: SFMSetup, model: AppModel) {
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Set up Neon Pup"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            window = w
        }
        window?.contentView = NSHostingView(rootView: SetupWizardView(setup: setup, model: model) { window?.close() })
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

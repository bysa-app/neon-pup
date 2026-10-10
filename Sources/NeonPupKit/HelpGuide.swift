import SwiftUI
import AppKit

/// The full guide behind "Help" (the maintainer 2026-10-10: anyone without context must be able to set up and use the
/// app from this alone). docs/GUIDE.md carries the same text (HelpGuideTests keeps them identical).
public enum HelpGuide {
    public enum Item: Sendable {
        case text(String)
        case step(String)
        /// A command or link: shown in monospace with a Copy link.
        case code(String)
    }

    /// Made-up examples of each link type (the maintainer 2026-10-10). HelpGuideTests checks that each one imports.
    public static let exampleLinks: [(label: String, link: String)] = [
        ("Everyday server (VLESS Reality):",
         "vless://11111111-2222-4333-8444-555555555555@203.0.113.10:443?encryption=none&security=reality&sni=www.apple.com&fp=chrome&pbk=fUP2s8T4LqCEhMDd7z8KNoqAYv3QBJ2rW0vmxyG8Zks&sid=ab12&type=tcp&flow=xtls-rprx-vision#Singapore"),
        ("Turbo server (Hysteria2):",
         "hy2://your-password@203.0.113.10:443?obfs=salamander&obfs-password=second-password&sni=www.bing.com#Singapore%20turbo"),
        ("Backup tunnel (VLESS over WebSocket):",
         "vless://11111111-2222-4333-8444-555555555555@proxy.example.com:443?encryption=none&security=tls&sni=proxy.example.com&type=ws&host=proxy.example.com&path=%2Fyour-path#Backup"),
    ]

    /// The health check page. Deliberately not a Claude page: if Neon Pup is not working, a Claude page
    /// would see the China connection (the maintainer 2026-10-10).
    public static let checkPage = "https://www.cloudflare.com/cdn-cgi/trace"
    public static let checkCommand = "curl -s https://www.cloudflare.com/cdn-cgi/trace | grep loc"

    /// Gets a stuck Mac back online without the app. Order matters: the helper re-seals whenever the engine
    /// stops while the block is wanted, so the "wanted" flag goes before the engine, and the rules go last.
    /// tools/emergency-drill.sh runs exactly this line.
    public static let emergencyCommand = "pkill -x NeonPup; sudo rm -f /private/var/db/co.holinic.neonpup/killswitch-wanted; sudo pkill -x sing-box; sleep 2; sudo pfctl -a com.apple/co.holinic.neonpup -F all; defaults write co.holinic.neonpup chinaMode -bool false"

    public static let sections: [(title: String, items: [Item])] = [
        ("What Neon Pup does", [
            .text("Neon Pup sends all of your Mac's internet through servers outside China, so blocked sites like Google, Instagram, WhatsApp and Claude work. While it is connected, Claude only sees your server's location."),
            .text("It lives in the menu bar as a butterfly next to the clock. Click the butterfly to open it."),
            .text("You need a Mac with macOS 13 or newer and at least one server link. Neon Pup comes without servers. The person or company that runs your servers gives you the links."),
        ]),
        ("Install (before you travel)", [
            .step("Download Neon-Pup.zip from neonpup.bysa.app, open it and drag Neon Pup into Applications."),
            .step("Open Neon Pup from Applications. The butterfly appears in the menu bar and the Your servers window opens."),
            .step("Add your servers (see the next section) and press Save my servers."),
            .step("Click the butterfly and press Wake me up. The first time, macOS asks you to allow Neon Pup. Switch it on in System Settings, under General, Login Items & Extensions, then press Wake me up again."),
            .step("When it says Connected, it works. Press Let me nap until you need it."),
        ]),
        ("Add your servers", [
            .text("A server link starts with vless://, hy2:// or hysteria2://. You get it from whoever runs your server, as text or as a file. Apps like Shadowrocket and Clash Verge can also export these links."),
            .step("Open the gear menu and choose Your servers."),
            .step("Paste your links into the box, one per line, and press Add these. If you got a file, press Import from file and pick it."),
            .step("If a line doesn't work, the window shows its line number and the problem. The other lines are still added."),
            .step("Rename the servers if you like, and use the arrows to put them in order. You can add up to 8."),
            .step("Press Save my servers. Your Mac's Keychain stores them, so you can delete the message or file you got them from."),
            .text("A server marked \"skips the safety check\" can't prove it is really your server. Use it only when nothing else works."),
        ]),
        ("What server links look like", [
            .text("Each link is one line. These examples use made-up values."),
        ] + exampleLinks.flatMap { [Item.text($0.label), Item.code($0.link)] } + [
            .text("The part after # is the name Neon Pup shows. A servers file is a plain text file (.txt) with one link on each line."),
        ]),
        ("Turn it on and off", [
            .text("Wake me up connects. While it connects it says Sniffing for a server. Wait for Connected before you open anything."),
            .text("Let me nap disconnects, and your Mac goes back to its normal internet."),
            .text("Start when my Mac starts (gear menu) opens Neon Pup when you log in. It still waits for you to press Wake me up."),
        ]),
        ("Check that it works", [
            .text("Don't test with a Claude page. If Neon Pup isn't working, that page would see your China connection."),
            .step("With Neon Pup connected, open this page in your browser:"),
            .code(checkPage),
            .step("Find the line that starts with loc=. It shows the country your internet comes from, as a two-letter code: loc=SG is Singapore, loc=US is America."),
            .step("If it shows loc=CN, Neon Pup isn't protecting you. Press Go offline (or Let me nap), don't open Claude, and see Get help from Claude below."),
            .text("Or in Terminal:"),
            .code(checkCommand),
        ]),
        ("Secure, Fast and Manual", [
            .text("Claude uses the top server in your list that works, in every mode. That covers claude.ai, the Claude desktop app and Claude Code. If that server stops working, Claude moves to the next one down."),
            .text("Secure (the default): the rest of your internet follows the same order. Use it for accounts that check where you log in from, like Google, banks and Instagram."),
            .text("Fast: everything except Claude uses whichever server answers fastest right now. Good for video."),
            .text("Manual: everything except Claude uses the server you pick. Hearts show how fast each server is, and more hearts means faster. If your pick stops working, Neon Pup falls back to your list order and tells you."),
            .text("Put the server you want Claude on at the top of the list. A server near China, such as Singapore, is usually fastest."),
        ]),
        ("If the connection drops", [
            .text("While Neon Pup is connected, nothing leaves your Mac except through your servers. If the connection drops, Neon Pup blocks the internet instead of letting apps fall back to the local connection, and says \"I paused the internet to keep you safe\"."),
            .text("Press Wake me up to try again. Outside China mode you can also press Back to normal internet."),
        ]),
        ("China mode", [
            .text("Turn China mode on (gear menu) before you join any Wi-Fi in China. Turn it off when you leave."),
            .text("With China mode on, your Mac has no internet at all unless Neon Pup is connected. Nothing can slip out over the local connection while Neon Pup starts, after a crash or after a restart. The big button says Go offline instead of Let me nap, because disconnecting leaves you offline."),
            .text("With China mode off, Let me nap gives you your normal internet back. Use that outside China."),
        ]),
        ("Time zone", [
            .text("If your Mac is set to China, Hong Kong or Macau time, Neon Pup switches it to Singapore while connected. The clock shows the same time. Apps like Claude can read your time zone, and this keeps it in line with your server. Neon Pup switches it back when you disconnect. Other time zones stay as they are."),
        ]),
        ("Wi-Fi with a login page (hotels, airports, cafes)", [
            .text("Some networks make you log in on a web page first. Normally your Mac shows that page by itself when you join. While Neon Pup is on, the page can't load, because your servers are unreachable until you log in."),
            .step("Join the Wi-Fi from the Wi-Fi menu."),
            .step("If Neon Pup shows Securely open public Wi-Fi login, press it. A browser tab opens and the network shows its login page there."),
            .step("Log in. Neon Pup closes the login window by itself as soon as your servers answer. You can also press Done."),
            .text("For up to 5 minutes your browser uses the local connection so the login page can load. Claude stays on your servers the whole time. Don't open other sites until it says Connected again."),
            .text("In China mode the Mac's own login pop-up can't load. Close it and use the button instead."),
        ]),
        ("Other VPN apps", [
            .text("Neon Pup won't connect while another VPN app is on, such as Clash Verge or a work VPN. Quit that app, then press Wake me up."),
        ]),
        ("What the messages mean", [
            .text("\"I need a one-time OK in System Settings\": press Open System Settings, switch Neon Pup on under Login Items & Extensions, then press Wake me up."),
            .text("\"Add your servers first\": open the gear menu, choose Your servers and add at least one."),
            .text("\"Another app is changing your internet\": quit your other VPN app."),
            .text("\"All servers are sleepy, I'll keep trying\": none of your servers answers. On Wi-Fi with a login page, use the login button. Otherwise try another network, or ask whoever runs your servers whether they are up."),
            .text("\"No internet at all, check the Wi-Fi\": the Wi-Fi itself isn't working."),
            .text("\"This server is blocked here, trying another\" (Manual): pick a different server."),
            .text("\"I couldn't block the internet\": the safety block failed. Turn Wi-Fi off so nothing leaks, then copy a report (below) and send it to whoever runs your servers."),
        ]),
        ("Stuck offline?", [
            .step("In China mode you're offline until Neon Pup connects. Press Wake me up."),
            .step("Still offline? Turn China mode off in the gear menu, then press Let me nap."),
            .step("Can't see the butterfly? Open Neon Pup from Applications. On a MacBook with a notch, menu bar icons can hide behind it, so quit a few other menu bar apps."),
            .step("Still blocked? Use Emergency below."),
        ]),
        ("Emergency: get your internet back", [
            .text("Use this if nothing else works and your Mac stays offline."),
            .step("Open Terminal (in Applications, then Utilities)."),
            .step("Paste this line and press Return. Type your Mac password when asked. It doesn't show as you type."),
            .code(emergencyCommand),
            .step("This quits Neon Pup, lifts its block and turns China mode off. Your internet works again."),
            .step("Still offline? Drag Neon Pup from Applications to the Trash and restart your Mac. Then download it again from neonpup.bysa.app."),
            .text("If your clock shows the wrong time zone afterwards, set it in System Settings, General, Date & Time."),
        ]),
        ("Remove Neon Pup", [
            .step("Turn China mode off and press Let me nap."),
            .step("Choose Quit in the gear menu, then drag Neon Pup from Applications to the Trash."),
        ]),
        ("Get help from Claude", [
            .text("Press Copy a report below. It copies a short description of Neon Pup for Claude, what Neon Pup is doing, how fast each server answers and its last 200 log lines. Server addresses, passwords and keys are hidden. The log can name sites that failed to load."),
            .text("Paste it into a chat with Claude or another assistant and ask what's wrong. Only do that while Neon Pup says Connected, or from a device with its own safe connection, such as your phone. You can also send it to whoever runs your servers."),
        ]),
    ]

    /// Section items as shown: steps numbered within their section; `isCode` marks commands and links.
    public static func lines(_ items: [Item]) -> [(text: String, isCode: Bool)] {
        var number = 0
        return items.map { item in
            switch item {
            case .text(let t): return (t, false)
            case .step(let t): number += 1; return ("\(number). \(t)", false)
            case .code(let t): return (t, true)
            }
        }
    }

    /// Plain-text version for docs/GUIDE.md.
    public static var markdown: String {
        sections.map { section in
            "## \(section.title)\n\n" + lines(section.items)
                .map { $0.isCode ? "```\n\($0.text)\n```" : $0.text }.joined(separator: "\n\n")
        }.joined(separator: "\n\n") + "\n"
    }

    /// Every word of the guide, for checks.
    public static var allText: String {
        sections.flatMap { [$0.title] + lines($0.items).map(\.text) }.joined(separator: " ")
    }
}

struct GuideView: View {
    let copyReport: () async -> String
    @State private var copied = false

    var body: some View {
        ScrollView { content }
            .frame(width: 440, height: 620)
            .background(Theme.night)
    }

    /// The guide without scrolling (the gallery renders this; ImageRenderer cannot draw a ScrollView).
    var content: some View {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(HelpGuide.sections, id: \.title) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title).font(Theme.rounded(15, .bold)).foregroundStyle(Theme.pink)
                        ForEach(Array(HelpGuide.lines(section.items).enumerated()), id: \.offset) { item in
                            if item.element.isCode {
                                CodeLine(text: item.element.text)
                            } else {
                                Text(item.element.text)
                                    .font(Theme.rounded(13)).foregroundStyle(Theme.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                HStack(spacing: 8) {
                    TextLink(title: copied ? "Copied" : "Copy a report") {
                        Task {
                            let report = await copyReport()
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(report, forType: .string)
                            copied = true
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            copied = false
                        }
                    }
                    if copied {
                        Text("Paste it into a message").font(Theme.rounded(12)).foregroundStyle(Theme.textDim)
                    }
                }
            }
            .padding(20)
            .frame(width: 440)
            .background(Theme.night)
    }
}

/// A command or link in the guide: monospace, selectable, with a Copy link so nobody has to retype it.
struct CodeLine: View {
    let text: String
    @State private var copied = false
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(text)
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.blush)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextLink(title: copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
                Task { try? await Task.sleep(nanoseconds: 2_000_000_000); copied = false }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.nightRaised))
    }
}

@MainActor
public enum GuideWindow {
    private static var window: NSWindow?

    public static func show(copyReport: @escaping () async -> String) {
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Neon Pup help"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            window = w
        }
        window?.contentView = NSHostingView(rootView: GuideView(copyReport: copyReport))
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

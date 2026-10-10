import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NeonPupCore

/// "Your servers" (own servers, 2026-10-10): paste share links or import a file, name and order the roads.
struct RoadsSetupView: View {
    @ObservedObject var model: AppModel
    @State private var draft: [RoadSpec]
    @State private var pasted = ""
    @State private var rejected: [(number: Int, message: String)] = []
    @State private var saved = false
    @State private var saving = false
    /// A failed save says so instead of doing nothing (Fable review #2).
    @State private var saveFailed = false
    let close: () -> Void

    init(model: AppModel, close: @escaping () -> Void) {
        self.model = model
        self.close = close
        _draft = State(initialValue: model.roadSpecs)
    }

    static let linksTip = "A server link starts with vless://, hy2:// or hysteria2://. You get it from whoever runs your server, for example your provider's website or a message from the person who set it up. Apps like Shadowrocket and Clash Verge can also share or export them."
    static let fileTip = "A plain text file (.txt) with one server link on each line, for example a file the person who runs your servers sent you."

    static func label(_ kind: RoadKind) -> String {
        switch kind {
        case .reality: return "Everyday server"
        case .hysteria2: return "Turbo server"
        case .websocket: return "Backup tunnel"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your servers").font(Theme.rounded(20, .bold)).foregroundStyle(Theme.pink)
            Text("Neon Pup sends your internet through these servers. Whoever runs them gives you a link for each one.")
                .font(Theme.rounded(12)).foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text("Paste server links, one per line").font(Theme.rounded(12, .medium)).foregroundStyle(Theme.text)
                InfoTip(text: Self.linksTip)
            }
            HStack(alignment: .top, spacing: 10) {
                TextEditor(text: $pasted)
                    .font(.system(size: 11, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 70)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.nightRaised))
                TextLink(title: "Add these") { add(pasted); pasted = "" }
                    .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.top, 6)
            }
            HStack(spacing: 6) {
                TextLink(title: "Import from file") { importFile() }
                InfoTip(text: Self.fileTip)
            }
            ForEach(Array(rejected.enumerated()), id: \.offset) { item in
                // Never echo the link: its start holds the user id or password (review).
                Text("Line \(item.element.number): \(item.element.message)")
                    .font(Theme.rounded(11)).foregroundStyle(Theme.blush)
            }
            if !draft.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(draft.enumerated()), id: \.offset) { item in row(item.offset, item.element) }
                }
                Text("Claude always uses the top server that works. Use the arrows to change the order. In Secure mode the rest of your internet follows the same order.")
                    .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            GlowButton(title: saved ? "Saved" : "Save my servers", wakes: true) {
                Task {
                    let named = draft.map { road -> RoadSpec in
                        var r = road
                        r.name = ShareLinkParser.finishTypedName(r.name)
                        return r
                    }
                    saving = true
                    saved = await model.setRoads(named)
                    saving = false
                    saveFailed = !saved
                    if saved { close() }
                }
            }
            .disabled(draft.isEmpty || saving)
            if saveFailed {
                Text("I couldn't save your servers. Try again")
                    .font(Theme.rounded(11)).foregroundStyle(Theme.blush)
            }
        }
        .padding(18)
        .frame(width: 380)
        .background(Theme.night)
    }

    private func row(_ index: Int, _ road: RoadSpec) -> some View {
        HStack(spacing: 8) {
            Text("\(index + 1)").font(Theme.rounded(13, .bold)).foregroundStyle(Theme.teal).frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                // Guarded: SwiftUI can read an outgoing row after it was deleted (review).
                TextField("Name", text: Binding(
                    get: { index < draft.count ? draft[index].name : "" },
                    set: { if index < draft.count { draft[index].name = ShareLinkParser.cleanTypedName($0) } }))
                    .textFieldStyle(.plain).font(Theme.rounded(13, .medium)).foregroundStyle(Theme.text)
                Text(Self.label(road.kind) + (road.isUnpinned ? ", skips the safety check" : ""))
                    .font(Theme.rounded(11)).foregroundStyle(road.isUnpinned ? Theme.blush : Theme.textDim)
            }
            Spacer()
            iconButton("chevron.up", enabled: index > 0) { draft.swapAt(index, index - 1) }
            iconButton("chevron.down", enabled: index < draft.count - 1) { draft.swapAt(index, index + 1) }
            iconButton("trash", enabled: true) { draft.remove(at: index) }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.nightRaised))
    }

    private func iconButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold))
                .foregroundStyle(enabled ? Theme.teal : Theme.textDim.opacity(0.3))
        }
        .buttonStyle(.plain).disabled(!enabled)
    }

    private func add(_ text: String) {
        rejected = []
        for item in ShareLinkParser.parseAll(text) {
            switch item.result {
            case .success(let road) where draft.count < RoadValidator.maxRoads: draft.append(road)
            case .success: rejected.append((item.number, "Only \(RoadValidator.maxRoads) servers fit"))
            case .failure(let error): rejected.append((item.number, error.message))
            }
        }
        saved = false
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        add(text)
    }
}

@MainActor
public enum RoadsWindow {
    private static var window: NSWindow?

    public static func show(model: AppModel) {
        let w = window ?? NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                                   backing: .buffered, defer: false)
        w.title = "Your servers"
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: RoadsSetupView(model: model) { window?.close() })
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

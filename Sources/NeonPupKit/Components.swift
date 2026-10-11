import SwiftUI
import AppKit
import NeonPupCore

public struct GlowButton: View {
    let title: String
    let wakes: Bool
    let action: () -> Void
    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.rounded(20, .bold))
                .foregroundStyle(wakes ? Theme.night : Theme.teal)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    RoundedRectangle(cornerRadius: Theme.corner)
                        .fill(wakes ? AnyShapeStyle(LinearGradient(colors: [Theme.pink, Theme.blush], startPoint: .leading, endPoint: .trailing))
                                    : AnyShapeStyle(Theme.nightRaised))
                )
                .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(wakes ? Theme.pink : Theme.teal, lineWidth: 1.5))
                .neonGlow(wakes ? Theme.pink : Theme.teal, radius: 6)
        }
        .buttonStyle(.plain)
    }
}

public struct StatusLine: View {
    let text: String
    public var body: some View {
        Text(text).font(Theme.rounded(14, .medium)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }
}

public struct ModeToggle: View {
    let mode: RoadMode
    let change: (RoadMode) -> Void
    static let modes: [(RoadMode, String, String)] = [
        (.secure, "Secure", "Safest for your accounts"),
        (.fast, "Fast", "Quickest for videos"),
        (.manual, "Manual", "You pick the server"),
    ]
    public var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                ForEach(Self.modes, id: \.0) { entry in chip(entry.1, entry.0) }
            }
            Text(Self.modes.first { $0.0 == mode }?.2 ?? "")
                .font(Theme.rounded(11)).foregroundStyle(Theme.textDim)
        }
    }
    private func chip(_ title: String, _ value: RoadMode) -> some View {
        Button { change(value) } label: {
            Text(title).font(Theme.rounded(13)).frame(maxWidth: .infinity, minHeight: 30)
                .foregroundStyle(mode == value ? Theme.night : Theme.textDim)
                .background(Capsule().fill(mode == value ? Theme.teal : Theme.nightRaised))
        }
        .buttonStyle(.plain)
    }
}

public struct HeartsView: View {
    let count: Int
    public var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < count ? "heart.fill" : "heart")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(i < count ? Theme.pink : Theme.textDim.opacity(0.5))
            }
        }
    }
}

public struct RoadRow: View {
    let road: Road
    let hearts: Int?          // nil = not measured (VPN off)
    let selected: Bool
    let action: () -> Void
    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle().fill(selected ? Theme.pink : Color.clear).frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Theme.pink, lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(road.name).font(Theme.rounded(12, .medium))
                        .foregroundStyle(hearts == 0 ? Theme.textDim : Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if hearts == 0 {
                        Text("sleeping right now").font(Theme.rounded(11)).foregroundStyle(Theme.textDim)
                    }
                }
                Spacer(minLength: 4)
                if let hearts, hearts > 0 { HeartsView(count: hearts) }
            }
            .padding(.vertical, 6).padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Theme.nightRaised : Color.clear))
        }
        .buttonStyle(.plain)
    }
}

public struct FooterBar: View {
    let startsAtLogin: Bool
    let chinaMode: Bool
    var tunnelChinaSites = false
    var toggleTunnelChinaSites: () -> Void = {}
    let help: () -> Void
    let toggleLogin: () -> Void
    let toggleChinaMode: () -> Void
    let showGuide: () -> Void
    let showRoads: () -> Void
    let quit: () -> Void
    public var body: some View {
        HStack {
            Button(action: help) {
                Label("Help", systemImage: "questionmark.circle")
                    .font(Theme.rounded(12)).foregroundStyle(Theme.textDim)
            }
            .buttonStyle(.plain)
            Spacer()
            Menu {
                Button((chinaMode ? "\u{2713} " : "") + "China mode", action: toggleChinaMode)
                Button((tunnelChinaSites ? "\u{2713} " : "") + "Send Chinese sites through my servers", action: toggleTunnelChinaSites)
                Button((startsAtLogin ? "\u{2713} " : "") + "Start when my Mac starts", action: toggleLogin)
                Divider()
                Button("Your servers...", action: showRoads)
                Button("Help", action: showGuide)
                Button("Quit", action: quit)
            } label: {
                Image(systemName: "gearshape.fill").foregroundStyle(Theme.textDim)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
    }
}

/// A small text link (plain words, teal, underlined so it reads as a link: the maintainer 2026-10-10).
public struct TextLink: View {
    let title: String
    let action: () -> Void
    public var body: some View {
        Button(action: action) {
            Text(title).underline()
        }
        .buttonStyle(.plain).font(Theme.rounded(12, .bold)).foregroundStyle(Theme.teal)
        .onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
    }
}

/// A closed-by-default "why?" section: a teal title with a chevron, and plain text underneath once opened.
public struct Accordion: View {
    let title: String
    let paragraphs: [String]
    @State private var open: Bool
    public init(title: String, paragraphs: [String], startsOpen: Bool = false) {
        self.title = title
        self.paragraphs = paragraphs
        _open = State(initialValue: startsOpen)
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                    Text(title).font(Theme.rounded(12, .bold))
                }
                .foregroundStyle(Theme.teal)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
            if open {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { item in
                        Text(item.element).font(Theme.rounded(12)).foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.nightRaised))
            }
        }
    }
}

/// An info icon that explains the thing next to it: on hover (tooltip) and on click (bubble).
public struct InfoTip: View {
    let text: String
    @State private var open = false
    public var body: some View {
        Button { open.toggle() } label: {
            Image(systemName: "info.circle").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textDim)
        }
        .buttonStyle(.plain)
        .help(text)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            Text(text).font(Theme.rounded(12)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 260, alignment: .leading)
                .padding(12)
        }
    }
}

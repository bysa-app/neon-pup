import SwiftUI
import AppKit
import NeonPupCore

/// Vector butterfly, crisp at 18 pt. Off: template (system grey). On: pink wings, teal body. Busy: teal blink.
/// (the maintainer 2026-10-09: the dog head read as a ghost at menu bar size.)
struct Butterfly: View {
    enum Look { case resting, glowing, dim, busy }
    let look: Look

    private func wing(_ rect: CGRect, angle: CGFloat, s: CGFloat) -> Path {
        let center = CGPoint(x: rect.midX * s, y: rect.midY * s)
        let local = CGRect(x: -rect.width * s / 2, y: -rect.height * s / 2, width: rect.width * s, height: rect.height * s)
        return Path(roundedRect: local, cornerRadius: min(local.width, local.height) * 0.48)
            .applying(CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
    }

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 18
            var wings = Path()
            wings.addPath(wing(CGRect(x: 2.0, y: 2.6, width: 6.6, height: 6.2), angle: -0.35, s: s))   // upper left
            wings.addPath(wing(CGRect(x: 9.4, y: 2.6, width: 6.6, height: 6.2), angle: 0.35, s: s))    // upper right
            wings.addPath(wing(CGRect(x: 3.4, y: 9.0, width: 5.0, height: 5.4), angle: 0.45, s: s))    // lower left
            wings.addPath(wing(CGRect(x: 9.6, y: 9.0, width: 5.0, height: 5.4), angle: -0.45, s: s))   // lower right
            var body = Path(roundedRect: CGRect(x: 8.25 * s, y: 4.6 * s, width: 1.5 * s, height: 9.6 * s), cornerRadius: 0.75 * s)
            var antennae = Path()
            antennae.move(to: CGPoint(x: 8.6 * s, y: 5.0 * s))
            antennae.addQuadCurve(to: CGPoint(x: 6.4 * s, y: 1.6 * s), control: CGPoint(x: 8.2 * s, y: 2.2 * s))
            antennae.move(to: CGPoint(x: 9.4 * s, y: 5.0 * s))
            antennae.addQuadCurve(to: CGPoint(x: 11.6 * s, y: 1.6 * s), control: CGPoint(x: 9.8 * s, y: 2.2 * s))
            body.addEllipse(in: CGRect(x: 5.7 * s, y: 0.9 * s, width: 1.4 * s, height: 1.4 * s))
            body.addEllipse(in: CGRect(x: 10.9 * s, y: 0.9 * s, width: 1.4 * s, height: 1.4 * s))

            let wingColor: Color, bodyColor: Color
            switch look {
            case .resting: wingColor = .black; bodyColor = .black
            case .glowing: wingColor = Theme.pink; bodyColor = Theme.teal
            case .busy: wingColor = Theme.teal; bodyColor = Theme.teal
            case .dim: wingColor = Color.black.opacity(0.35); bodyColor = Color.black.opacity(0.35)
            }
            ctx.fill(wings, with: .color(wingColor))
            // no wing spots: round holes read as eyes at 18 pt
            ctx.blendMode = .destinationOut
            // gap between wings and body so the shapes read separately
            ctx.stroke(Path(roundedRect: CGRect(x: 8.25 * s, y: 4.6 * s, width: 1.5 * s, height: 9.6 * s), cornerRadius: 0.75 * s),
                       with: .color(.black), lineWidth: 1.0 * s)
            ctx.blendMode = .normal
            ctx.fill(body, with: .color(bodyColor))
            ctx.stroke(antennae, with: .color(bodyColor), style: StrokeStyle(lineWidth: 0.9 * s, lineCap: .round))
        }
        .frame(width: 18, height: 18)
    }
}

public struct MenuBarIcon: View {
    let phase: Phase
    public init(phase: Phase) { self.phase = phase }

    /// Rendered once and reused: a label that builds a new NSImage on every update makes the status
    /// item request another update, forever (Task 11 drill: launch spun in Update.dispatchActions and
    /// quit hung). Same reason there is no timer-driven blink.
    @MainActor static let images: [Butterfly.Look: NSImage] = {
        var out: [Butterfly.Look: NSImage] = [:]
        for look in [Butterfly.Look.resting, .glowing, .busy] {
            let renderer = ImageRenderer(content: Butterfly(look: look))
            renderer.scale = 2
            let image = renderer.nsImage ?? NSImage()
            image.isTemplate = look == .resting
            out[look] = image
        }
        return out
    }()

    static func look(for phase: Phase) -> Butterfly.Look {
        switch phase {
        case .connected: return .glowing
        case .connecting, .switching, .hotelLogin, .trouble: return .busy
        case .off, .failed: return .resting
        }
    }

    public var body: some View {
        Image(nsImage: Self.images[Self.look(for: phase)] ?? NSImage())
    }
}

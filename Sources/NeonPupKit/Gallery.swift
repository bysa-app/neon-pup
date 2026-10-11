import SwiftUI
import AppKit
import NeonPupCore

/// Renders the real PanelView in every state to PNGs for review: NeonPup --render-gallery <dir>
@MainActor
public enum Gallery {
    static let states: [(String, Phase, RoadMode)] = [
        ("01-off", .off, .secure),
        ("02-connecting", .connecting, .secure),
        ("03-connected-secure", .connected, .secure),
        ("04-connected-manual", .connected, .manual),
        ("05-road-closed", .trouble(.roadClosed), .manual),
        ("06-all-sleepy", .trouble(.allRoadsSleepy), .fast),
        ("07-no-internet", .trouble(.noInternet), .secure),
        ("08-needs-ok", .trouble(.needsApproval), .secure),
        ("09-paused", .failed, .secure),
        ("10-hotel-login", .hotelLogin, .secure),
        ("11-other-vpn", .trouble(.otherVPN), .secure),
        ("12-not-sealed", .trouble(.notSealed), .secure),
    ]

    public static func render(to dir: URL) -> [URL] {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var out: [URL] = []
        for (name, phase, mode) in states {
            let model = AppModel.preview(phase: phase, mode: mode, pickedRoad: mode == .manual ? "road-2" : nil,
                                         delays: ["road-1": 58, "road-2": 61, "road-3": 280, "road-4": 310])
            let renderer = ImageRenderer(content: PanelView(model: model, appVersion: "1.0.0"))
            renderer.scale = 2
            if let tiff = renderer.nsImage?.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                let url = dir.appendingPathComponent("\(name).png")
                try? png.write(to: url)
                out.append(url)
            }
        }
        for (name, model) in [("13-roads-setup", AppModel.preview(phase: .off)),
                              ("14-roads-empty", AppModel.preview(phase: .trouble(.noRoads), roads: []))] {
            let renderer = ImageRenderer(content: RoadsSetupView(model: model, close: {}))
            renderer.scale = 2
            if let tiff = renderer.nsImage?.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                let url = dir.appendingPathComponent("\(name).png")
                try? png.write(to: url)
                out.append(url)
            }
        }
        do {
            let renderer = ImageRenderer(content: GuideView(copyReport: { "" }).content)
            renderer.scale = 2
            if let tiff = renderer.nsImage?.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                let url = dir.appendingPathComponent("15-help.png")
                try? png.write(to: url)
                out.append(url)
            }
        }
        // Setup wizard, every page (bridge answers nothing: renders only, no system calls take effect).
        let previewDefaults = UserDefaults(suiteName: "gallery-wizard") ?? .standard
        for step in SFMSetup.Step.allCases {
            let setup = SFMSetup(bridge: SFMBridge(run: { _, _ in "" }), defaults: previewDefaults)
            setup.step = step
            let model = AppModel.preview(phase: .off)
            let renderer = ImageRenderer(content: SetupWizardView(setup: setup, model: model, close: {}))
            renderer.scale = 2
            if let tiff = renderer.nsImage?.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                let url = dir.appendingPathComponent(String(format: "20-wizard-%02d.png", step.rawValue))
                try? png.write(to: url)
                out.append(url)
            }
        }
        // The install page with its "Why do I need SFM?" section opened.
        do {
            let setup = SFMSetup(bridge: SFMBridge(run: { _, _ in "" }), defaults: previewDefaults)
            setup.step = .install
            let renderer = ImageRenderer(content: SetupWizardView(setup: setup, model: AppModel.preview(phase: .off),
                                                                  close: {}, whyOpen: true))
            renderer.scale = 2
            if let tiff = renderer.nsImage?.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                let url = dir.appendingPathComponent("20-wizard-02-why-open.png")
                try? png.write(to: url)
                out.append(url)
            }
        }
        for (name, phase) in [("menubar-off", Phase.off), ("menubar-on", .connected), ("menubar-busy", .connecting)] {
            let renderer = ImageRenderer(content: MenuBarIcon(phase: phase).frame(width: 18, height: 18).padding(4).background(Color.gray.opacity(0.2)))
            renderer.scale = 4
            if let tiff = renderer.nsImage?.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                let url = dir.appendingPathComponent("\(name).png")
                try? png.write(to: url)
                out.append(url)
            }
        }
        return out
    }
}

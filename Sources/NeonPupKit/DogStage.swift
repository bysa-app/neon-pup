import SwiftUI
import AppKit
import NeonPupCore

public struct DogStage: View {
    let mood: Mood

    static func art(_ name: String) -> NSImage? {
        guard let path = Bundle.main.resourcePath else { return nil }
        return NSImage(contentsOfFile: path + "/Art/\(name).png")
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            if let backdrop = Self.art("backdrop") {
                Image(nsImage: backdrop).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Theme.purple, Theme.night], startPoint: .top, endPoint: .bottom)
            }
            Group {
                if let dog = Self.art("dog-\(mood.rawValue)") {
                    Image(nsImage: dog).resizable().scaledToFit()
                } else {
                    Image(systemName: "pawprint.fill").resizable().scaledToFit().padding(30).foregroundStyle(Theme.pink)
                }
            }
            .frame(height: 150)
            .neonGlow(mood == .happy ? Theme.pink : Theme.purple, radius: 10)
        }
        .frame(width: Theme.panelWidth - 32, height: 200)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
        // No animation on purpose: the bobbing dog read as the app "floating in and out" (the maintainer 2026-10-09).
    }
}

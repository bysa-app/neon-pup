import Foundation

/// How the user wants her roads chosen (the maintainer 2026-10-10). Secure is the default.
public enum RoadMode: String, Sendable, CaseIterable {
    case secure, fast, manual

    /// Reads the stored value; the old "auto" becomes Secure, anything unknown too.
    public init(stored: String?) {
        self = RoadMode(rawValue: stored ?? "") ?? .secure
    }
}

public struct RoadSelection: Equatable, Sendable {
    /// What the "choice" selector points at: a road tag, or "auto" (fastest) in Fast mode.
    public let choice: String
    /// What the "claude" selector points at. Always the first working road in the fixed order.
    public let claude: String
    /// Manual mode only: the user's road is down and the fixed order took over.
    public let pickedRoadDown: Bool

    public init(choice: String, claude: String, pickedRoadDown: Bool) {
        self.choice = choice
        self.claude = claude
        self.pickedRoadDown = pickedRoadDown
    }
}

public enum RoadPolicy {
    /// `order` is the person's list (first = where Claude goes while it works). nil when no road answers.
    /// `current` is the server Claude is on now: it stays while it works, so Claude doesn't snap back to the top
    /// of the list and lose its connections (Codex full review 2026-10-10). Otherwise the first working one.
    public static func selection(mode: RoadMode, picked: String?, alive: Set<String>, order: [String],
                                 current: String? = nil) -> RoadSelection? {
        guard let top = order.first(where: alive.contains) else { return nil }
        let first = current.flatMap { order.contains($0) && alive.contains($0) ? $0 : nil } ?? top
        switch mode {
        case .secure:
            return RoadSelection(choice: first, claude: first, pickedRoadDown: false)
        case .fast:
            return RoadSelection(choice: "auto", claude: first, pickedRoadDown: false)
        case .manual:
            if let picked, alive.contains(picked) {
                return RoadSelection(choice: picked, claude: first, pickedRoadDown: false)
            }
            return RoadSelection(choice: first, claude: first, pickedRoadDown: picked != nil)
        }
    }
}

import Foundation

public struct Road: Equatable, Sendable {
    public let tag: String
    public let name: String
}

/// The person's own roads, in their order (own roads, 2026-10-10). Tags match ConfigTemplate.
public enum Roads {
    public static func from(_ specs: [RoadSpec]) -> [Road] {
        zip(ConfigTemplate.tags(count: specs.count), specs).map { Road(tag: $0, name: $1.name) }
    }
}

public enum Hearts {
    /// 0 means "sleeping right now": no answer (the clash API reports failures as no delay or 0).
    public static func count(delayMs: Int?) -> Int {
        guard let delay = delayMs, delay > 0 else { return 0 }
        if delay < 150 { return 3 }
        if delay < 400 { return 2 }
        return 1
    }
}

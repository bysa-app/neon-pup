import Foundation

public enum LogLine {
    static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
    }

    /// The last ERROR or FATAL line from sing-box output, without terminal colour codes.
    public static func lastError(in text: String) -> String? {
        return plain(text).split(separator: "\n")
            .last { $0.contains("ERROR") || $0.contains("FATAL") }
            .map { String($0).trimmingCharacters(in: .whitespaces) }
    }
}

/// The engine's recent output, for the help report (the maintainer 2026-10-10). Keeps the last `capacity` complete
/// lines; output arrives in arbitrary chunks, so a line split across reads is joined first.
public struct LogRing: Sendable {
    public let capacity: Int
    public private(set) var lines: [String] = []
    private var partial = ""

    public init(capacity: Int = 200) { self.capacity = capacity }

    public mutating func append(_ chunk: String) {
        var text = partial + LogLine.plain(chunk)
        partial = ""
        if !text.hasSuffix("\n"), let cut = text.lastIndex(of: "\n") {
            partial = String(text[text.index(after: cut)...])
            text = String(text[...cut])
        } else if !text.hasSuffix("\n") {
            partial = text
            return
        }
        lines += text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if lines.count > capacity { lines.removeFirst(lines.count - capacity) }
    }

    public var text: String { (lines + (partial.isEmpty ? [] : [partial])).joined(separator: "\n") }
}

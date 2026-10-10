import Foundation

public enum LogLine {
    /// The last ERROR or FATAL line from sing-box output, without terminal colour codes.
    public static func lastError(in text: String) -> String? {
        let plain = text.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
        return plain.split(separator: "\n")
            .last { $0.contains("ERROR") || $0.contains("FATAL") }
            .map { String($0).trimmingCharacters(in: .whitespaces) }
    }
}

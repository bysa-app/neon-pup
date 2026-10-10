import Foundation

public enum TimeZonePolicy {
    public static let singapore = "Asia/Singapore"
    /// All UTC+8 names for mainland China, Hong Kong and Macau. Asia/Urumqi (UTC+6) is excluded
    /// on purpose: swapping it would change the clock.
    static let chinaZones: Set<String> = ["Asia/Shanghai", "Asia/Hong_Kong", "Asia/Macau", "Asia/Chongqing", "Asia/Harbin", "PRC"]

    public static func replacement(for zone: String) -> String? {
        chinaZones.contains(zone) ? singapore : nil
    }
}

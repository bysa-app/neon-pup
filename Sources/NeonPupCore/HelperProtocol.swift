import Foundation

@objc public protocol NeonPupHelperProtocol {
    /// The helper builds the engine settings itself from its verified copy of the app.
    /// Reply: control port and password on success, or an error.
    /// `roads` is a JSON list of RoadSpec; the helper re-validates every field before use.
    func start(roads: Data, withReply reply: @escaping (Int, String?, String?) -> Void)
    func stop(withReply reply: @escaping () -> Void)
    func status(withReply reply: @escaping (Bool, String?) -> Void)
    /// Reply is the zone that was set, or nil when the current zone is not a China zone.
    func applyTimeZone(withReply reply: @escaping (String?) -> Void)
    func restoreTimeZone(withReply reply: @escaping () -> Void)
    /// Kill switch on (or refreshed for new network interfaces) / off. Reply nil = done.
    func setKillSwitch(_ on: Bool, withReply reply: @escaping (String?) -> Void)
    /// Diagnostics: loaded kill switch rules with counters, pf status and the main ruleset.
    func killSwitchReport(withReply reply: @escaping (String) -> Void)
    func version(withReply reply: @escaping (String) -> Void)
}

public enum HelperConstants {
    public static let appBundleID = "co.holinic.neonpup"
    public static let machService = "co.holinic.neonpup.helper"
    public static let plistName = "co.holinic.neonpup.helper.plist"
    public static let teamID = "43YSGDB8TC"
    /// Developer ID Application certificates only (not Apple Development), from Holinic's team.
    /// OIDs: 1.2.840.113635.100.6.2.6 = Developer ID intermediate, ...6.1.13 = Developer ID Application leaf.
    public static func developerIDRequirement(identifier: String) -> String {
        "anchor apple generic and identifier \"\(identifier)\""
            + " and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
            + " and certificate leaf[subject.OU] = \"\(teamID)\""
    }

    /// Only Neon Pup signed with Holinic's Developer ID may talk to the root helper.
    public static let clientRequirement = developerIDRequirement(identifier: appBundleID)
    public static let version = "11"
}

/// How the app reaches the running engine's local control interface.
public struct EngineAccess: Equatable, Sendable {
    public let port: Int
    public let secret: String
    public init(port: Int, secret: String) { self.port = port; self.secret = secret }
}

public enum StartResult: Equatable, Sendable {
    case started(EngineAccess)
    case failed(String)
}

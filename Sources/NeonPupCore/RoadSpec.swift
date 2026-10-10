import Foundation
import Darwin

public enum RoadKind: String, Codable, Sendable, CaseIterable {
    case reality, websocket, hysteria2
}

/// One road, from a pasted share link. Only strict, typed fields: nothing here ever becomes a JSON key.
/// Checked by RoadValidator in the app and again in the root helper.
public struct RoadSpec: Codable, Equatable, Sendable {
    public var kind: RoadKind
    public var name: String
    public var host: String
    public var port: Int
    public var hopFrom: Int?
    public var hopTo: Int?
    public var uuid: String?
    public var password: String?
    public var serverName: String?
    public var publicKey: String?
    public var shortID: String?
    public var fingerprint: String?
    public var path: String?
    public var wsHost: String?
    public var obfsPassword: String?
    public var publicKeySHA256: String?
    public var allowInsecure: Bool

    public init(kind: RoadKind, name: String, host: String, port: Int, hopFrom: Int? = nil, hopTo: Int? = nil,
                uuid: String? = nil, password: String? = nil, serverName: String? = nil, publicKey: String? = nil,
                shortID: String? = nil, fingerprint: String? = nil, path: String? = nil, wsHost: String? = nil,
                obfsPassword: String? = nil, publicKeySHA256: String? = nil, allowInsecure: Bool = false) {
        self.kind = kind; self.name = name; self.host = host; self.port = port; self.hopFrom = hopFrom
        self.hopTo = hopTo; self.uuid = uuid; self.password = password; self.serverName = serverName
        self.publicKey = publicKey; self.shortID = shortID; self.fingerprint = fingerprint; self.path = path
        self.wsHost = wsHost; self.obfsPassword = obfsPassword; self.publicKeySHA256 = publicKeySHA256
        self.allowInsecure = allowInsecure
    }

    /// Hysteria2 roads that skip certificate checks without a pin can be impersonated.
    public var isUnpinned: Bool { kind == .hysteria2 && allowInsecure && publicKeySHA256 == nil }

    /// The same road whatever it is called.
    public func sameRoad(as other: RoadSpec) -> Bool {
        var renamed = other
        renamed.name = name
        return renamed == self
    }
}

/// Field checks. Empty result = valid. Problem names are plain words for the setup screen.
public enum RoadValidator {
    public static let maxRoads = 8
    static let fingerprints: Set<String> = ["chrome", "firefox", "safari", "ios", "edge", "random"]

    /// Whole-string match. Patterns are written with ^...$; they are anchored with \A...\z here so no
    /// engine can ever accept a trailing newline (security review; ICU did not, checked 2026-10-10).
    static func matches(_ s: String, _ pattern: String) -> Bool {
        var strict = pattern
        if strict.hasPrefix("^") { strict = "\\A" + strict.dropFirst() }
        if strict.hasSuffix("$") { strict = strict.dropLast() + "\\z" }
        return s.range(of: strict, options: .regularExpression) != nil
    }

    /// Plain ASCII only (no look-alike letters), no spaces, quotes, backslashes or control characters.
    static func isHostname(_ s: String) -> Bool {
        guard s.count <= 253, s.allSatisfy({ $0.isASCII }) else { return false }
        return matches(s, #"^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$"#)
    }
    /// A real IPv6 address, not just allowed characters (Codex review: "[:]" passed).
    static func isIPv6(_ s: String) -> Bool {
        guard s.count <= 45, matches(s, #"^[0-9A-Fa-f:.]+$"#) else { return false }
        var address = in6_addr()
        return inet_pton(AF_INET6, s, &address) == 1
    }
    static func isSecret(_ s: String) -> Bool {
        (1...128).contains(s.count) && s.unicodeScalars.allSatisfy { $0.value > 0x20 && $0.value < 0x7F && $0 != "\"" && $0 != "\\" }
    }
    static func isName(_ s: String) -> Bool {
        (1...40).contains(s.count) && !s.contains("\"") && !s.contains("\\")
            && s.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) && !(0x202A...0x202E).contains($0.value)
                && !(0x2066...0x2069).contains($0.value) }
    }

    public static func problems(_ r: RoadSpec) -> [String] {
        var found: [String] = []
        if !isName(r.name) { found.append("name") }
        if !(isHostname(r.host) || isIPv6(r.host)) { found.append("address") }
        if !(1...65535).contains(r.port) { found.append("port") }
        if r.hopFrom != nil || r.hopTo != nil {
            if r.kind != .hysteria2 { found.append("extra fields") }
            if let from = r.hopFrom, let to = r.hopTo, (1...65535).contains(from), (1...65535).contains(to), from < to {} else {
                found.append("port range")
            }
        }
        let uuidPattern = #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#
        if let sni = r.serverName, !isHostname(sni) { found.append("disguise name") }
        switch r.kind {
        case .reality:
            if !matches(r.uuid ?? "", uuidPattern) { found.append("user id") }
            if r.serverName == nil { found.append("disguise name") }
            if !matches(r.publicKey ?? "", #"^[A-Za-z0-9_-]{43}$"#) { found.append("key") }
            if let sid = r.shortID, !(matches(sid, #"^[0-9a-f]{0,16}$"#) && sid.count % 2 == 0) { found.append("short id") }
            if let fp = r.fingerprint, !fingerprints.contains(fp) { found.append("fingerprint") }
            if r.path != nil || r.wsHost != nil || r.password != nil || r.obfsPassword != nil || r.publicKeySHA256 != nil
                || r.allowInsecure { found.append("extra fields") }
        case .websocket:
            if !matches(r.uuid ?? "", uuidPattern) { found.append("user id") }
            if r.serverName == nil { found.append("disguise name") }
            if !(matches(r.path ?? "", #"^/[A-Za-z0-9/_.~%-]{0,127}$"#)) { found.append("path") }
            if let h = r.wsHost, !isHostname(h) { found.append("disguise name") }
            if r.publicKey != nil || r.shortID != nil || r.password != nil || r.obfsPassword != nil
                || r.publicKeySHA256 != nil || r.allowInsecure || r.fingerprint != nil { found.append("extra fields") }
        case .hysteria2:
            if !isSecret(r.password ?? "") { found.append("password") }
            if let o = r.obfsPassword, !isSecret(o) { found.append("password") }
            if let pin = r.publicKeySHA256, !matches(pin, #"^[A-Za-z0-9+/]{43}=$"#) { found.append("pin") }
            if r.uuid != nil || r.publicKey != nil || r.shortID != nil || r.path != nil || r.wsHost != nil
                || r.fingerprint != nil { found.append("extra fields") }
        }
        var seen = Set<String>()
        return found.filter { seen.insert($0).inserted }
    }
}

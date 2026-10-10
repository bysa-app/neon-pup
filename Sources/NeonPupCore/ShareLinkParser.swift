import Foundation

public struct ShareLinkError: Error, Equatable, Sendable {
    public let message: String
    static let unsupported = ShareLinkError(message: "This link isn't something I understand")
    static let cannotPin = ShareLinkError(message: "This link locks to a safety key I can't check. Ask for a newer link")
    static func problems(_ list: [String]) -> ShareLinkError {
        ShareLinkError(message: "This link has a problem with: " + list.joined(separator: ", "))
    }
}

/// Turns vless:// and hysteria2:// share links into RoadSpecs (own roads, 2026-10-10). Parsed by hand:
/// URLComponents rejects hysteria2 port ranges. Every result passes RoadValidator or is refused.
public enum ShareLinkParser {
    /// `number` is the line as the person sees it, blank lines included (Fable review #5).
    public static func parseAll(_ text: String) -> [(number: Int, line: String, result: Result<RoadSpec, ShareLinkError>)] {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated()
            .map { ($0.offset + 1, $0.element.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.1.isEmpty }
            .map { ($0.0, $0.1, parse($0.1)) }
    }

    public static func parse(_ raw: String) -> Result<RoadSpec, ShareLinkError> {
        let link = raw.trimmingCharacters(in: .whitespaces)
        guard let schemeEnd = link.range(of: "://") else { return .failure(.unsupported) }
        let scheme = link[..<schemeEnd.lowerBound].lowercased()
        guard scheme == "vless" || scheme == "hysteria2" || scheme == "hy2" else { return .failure(.unsupported) }
        var rest = String(link[schemeEnd.upperBound...])

        var fragment = ""
        if let hash = rest.firstIndex(of: "#") { fragment = String(rest[rest.index(after: hash)...]); rest = String(rest[..<hash]) }
        var query: [String: String] = [:]
        if let q = rest.firstIndex(of: "?") {
            for pair in rest[rest.index(after: q)...].split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                // Decode names too: "%70inSHA256" must count as pinSHA256 (Codex review).
                guard let key = parts.first.map({ decode($0).lowercased() }) else { continue }
                query[key] = decode(parts.count > 1 ? parts[1] : "")
            }
            rest = String(rest[..<q])
        }
        if rest.hasSuffix("/") { rest.removeLast() }
        guard let at = rest.lastIndex(of: "@") else { return .failure(.unsupported) }
        let user = decode(String(rest[..<at]))
        let hostPort = String(rest[rest.index(after: at)...])

        guard let (host, portText) = splitHostPort(hostPort) else { return .failure(.problems(["address"])) }
        // Exactly "443" or "20000-50000"; anything else is refused, never rewritten (Codex review).
        guard RoadValidator.matches(portText, #"^[0-9]{1,5}(-[0-9]{1,5})?$"#) else {
            return .failure(.problems([portText.contains("-") ? "port range" : "port"]))
        }
        var port = Int(portText) ?? 0
        var hopFrom: Int?, hopTo: Int?
        let range = portText.split(separator: "-").compactMap { Int($0) }
        if range.count == 2 { hopFrom = range[0]; hopTo = range[1]; port = range[0] }

        let road: RoadSpec
        if scheme == "vless" {
            switch (query["security"], query["type"] ?? "tcp") {
            case ("reality", "tcp"):
                if let flow = query["flow"], flow != "xtls-rprx-vision" { return .failure(.unsupported) }
                road = RoadSpec(kind: .reality, name: cleanName(fragment), host: host, port: port, uuid: user,
                                serverName: query["sni"], publicKey: query["pbk"], shortID: query["sid"],
                                fingerprint: query["fp"] ?? "chrome")
            case ("tls", "ws"):
                road = RoadSpec(kind: .websocket, name: cleanName(fragment), host: host, port: port, uuid: user,
                                serverName: query["sni"] ?? host, path: query["path"] ?? "/", wsHost: query["host"])
            default:
                return .failure(.unsupported)
            }
            if hopFrom != nil { return .failure(.problems(["port range"])) }
        } else {
            if let obfs = query["obfs"], obfs != "salamander" { return .failure(.unsupported) }
            // sing-box can only pin the public key. A certificate pin we cannot enforce must not be dropped
            // silently (security review): refuse the link instead of skipping the check.
            if query["pinsha256"] != nil && query["pinpublickey"] == nil { return .failure(.cannotPin) }
            road = RoadSpec(kind: .hysteria2, name: cleanName(fragment), host: host, port: port, hopFrom: hopFrom,
                            hopTo: hopTo, password: user, serverName: query["sni"], obfsPassword: query["obfs-password"],
                            publicKeySHA256: query["pinpublickey"], allowInsecure: query["insecure"] == "1")
        }
        let problems = RoadValidator.problems(road)
        return problems.isEmpty ? .success(road) : .failure(.problems(problems))
    }

    static func decode(_ s: String) -> String { s.removingPercentEncoding ?? s }

    static func splitHostPort(_ s: String) -> (String, String)? {
        if s.hasPrefix("["), let close = s.firstIndex(of: "]") {
            let host = String(s[s.index(after: s.startIndex)..<close])
            let after = s[s.index(after: close)...]
            guard after.hasPrefix(":") else { return nil }
            return (host, String(after.dropFirst()))
        }
        guard let colon = s.lastIndex(of: ":") else { return nil }
        return (decode(String(s[..<colon])), String(s[s.index(after: colon)...]))
    }

    /// Names are cosmetic: clean them instead of refusing the link.
    /// For typing in the setup screen: drop characters names may not have, keep empty while typing.
    public static func cleanTypedName(_ typed: String) -> String {
        String(String.UnicodeScalarView(typed.unicodeScalars.filter { s in
            s != "\"" && s != "\\" && !CharacterSet.controlCharacters.contains(s)
                && !(0x202A...0x202E).contains(s.value) && !(0x2066...0x2069).contains(s.value)
        })).prefix(40).description
    }

    /// A name typed in the setup screen, as saved: kept as typed (no percent-decoding, Fable review #4),
    /// trimmed, never empty.
    public static func finishTypedName(_ typed: String) -> String {
        let name = cleanTypedName(typed).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Server" : name
    }

    public static func cleanName(_ fragment: String) -> String {
        let decoded = decode(fragment)
        let kept = decoded.unicodeScalars.filter { s in
            s != "\"" && s != "\\" && !CharacterSet.controlCharacters.contains(s)
                && !(0x202A...0x202E).contains(s.value) && !(0x2066...0x2069).contains(s.value)
        }
        let name = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Server" : String(name.prefix(40)).trimmingCharacters(in: .whitespaces)
    }
}

import Foundation
import CryptoKit

public struct RuntimeOptions: Sendable {
    /// Who runs the engine: Neon Pup's own helper (plain TUN, rules from the bundle) or SFM, sing-box's
    /// NetworkExtension app, which owns the tunnel and system DNS (2026-10-10, DNS fix for the China trip).
    public enum Platform: Sendable { case helper, sfm }
    public let resourcesPath: String
    public let apiPort: Int
    public let apiSecret: String
    public let platform: Platform
    public init(resourcesPath: String, apiPort: Int, apiSecret: String, platform: Platform = .helper) {
        self.resourcesPath = resourcesPath
        self.apiPort = apiPort
        self.apiSecret = apiSecret
        self.platform = platform
    }
}

public enum ConfigTemplateError: Error, Equatable {
    case noRoads, tooManyRoads
    case invalidRoad(index: Int, problems: [String])
}

/// Builds the whole sing-box config from checked RoadSpecs (own roads, 2026-10-10). The structure is fixed
/// here; user values only ever land in value positions, and every road is re-validated before use.
/// Keeps every protection of the earlier ConfigBuilder: TUN utun233 with strict routing, "claude" selector
/// in the user's order (never direct), Claude names resolved through the Claude roads, the hotel login
/// window (mode Direct, network DNS for everything but Claude), China lists from the app bundle.
public enum ConfigTemplate {
    public static let tunnelName = "utun233"
    public static let claudeDomains = ["claude.ai", "claude.com", "anthropic.com", "claudeusercontent.com", "clau.de"]

    public static func tags(count: Int) -> [String] { (1...max(count, 1)).prefix(count).map { "road-\($0)" } }

    public static func build(roads: [RoadSpec], options: RuntimeOptions) throws -> Data {
        guard !roads.isEmpty else { throw ConfigTemplateError.noRoads }
        guard roads.count <= RoadValidator.maxRoads else { throw ConfigTemplateError.tooManyRoads }
        for (index, road) in roads.enumerated() {
            let problems = RoadValidator.problems(road)
            if !problems.isEmpty { throw ConfigTemplateError.invalidRoad(index: index, problems: problems) }
        }
        let tags = tags(count: roads.count)
        var outbounds: [[String: Any]] = [
            ["tag": "choice", "type": "selector", "outbounds": ["auto"] + tags, "default": tags[0],
             "interrupt_exist_connections": true],
            ["tag": "claude", "type": "selector", "outbounds": tags, "default": tags[0],
             "interrupt_exist_connections": true],
            ["tag": "auto", "type": "urltest", "outbounds": tags, "url": "https://www.gstatic.com/generate_204",
             "interval": "2m", "tolerance": 80],
        ]
        for (road, tag) in zip(roads, tags) { outbounds.append(outbound(road, tag: tag)) }
        // Never used for traffic: its tag names the server list, so Neon Pup can check what SFM runs.
        if options.platform == .sfm { outbounds.append(["tag": fingerprintTag(roads: roads), "type": "direct"]) }
        outbounds.append(["tag": "direct", "type": "direct", "domain_resolver": "local-dns"])

        let resources = options.resourcesPath
        let root: [String: Any] = [
            "log": ["level": "warn", "timestamp": true],
            "dns": [
                "servers": [
                    ["tag": "proxy-dns", "type": "https", "server": "1.1.1.1", "detour": "claude"],
                    ["tag": "local-dns", "type": "udp", "server": "223.5.5.5"],
                    ["tag": "hotel-dns", "type": "dhcp"],
                ],
                "rules": [
                    ["domain_suffix": claudeDomains, "action": "route", "server": "proxy-dns"],
                    ["clash_mode": "Direct", "action": "route", "server": "hotel-dns"],
                    ["rule_set": "geosite-cn", "clash_mode": "Rule", "action": "route", "server": "local-dns"],
                ],
                "final": "proxy-dns",
            ],
            "inbounds": [tunInbound(options.platform)],
            "outbounds": outbounds,
            "route": [
                "default_domain_resolver": "local-dns",
                "rules": [
                    ["action": "sniff"],
                    ["protocol": "dns", "action": "hijack-dns"],
                    ["domain_suffix": claudeDomains, "action": "route", "outbound": "claude"],
                    ["clash_mode": "Direct", "action": "route", "outbound": "direct"],
                    ["ip_is_private": true, "action": "route", "outbound": "direct"],
                    ["rule_set": "geoip-cn", "clash_mode": "Rule", "action": "route", "outbound": "direct"],
                    ["rule_set": "geosite-cn", "clash_mode": "Rule", "action": "route", "outbound": "direct"],
                ],
                "rule_set": ruleSets(options.platform, resources: resources),
                "final": "choice",
                "auto_detect_interface": true,
            ],
            "experimental": experimental(options),
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    /// "np-" plus the first 12 hex digits of SHA-256 over the server list (order, names and fields).
    public static func fingerprintTag(roads: [RoadSpec]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(roads)) ?? Data()
        let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "np-" + hex.prefix(12)
    }

    static func tunInbound(_ platform: RuntimeOptions.Platform) -> [String: Any] {
        var tun: [String: Any] = ["tag": "tun-in", "type": "tun", "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
                                  "auto_route": true, "strict_route": true]
        switch platform {
        case .helper:
            tun["interface_name"] = tunnelName; tun["stack"] = "mixed"
        case .sfm:
            // Measured on SFM 1.14.3 (2026-10-10): macOS names the interface; without auto_route NetworkExtension
            // installs no routes; the default stack fails ("bind: can't assign requested address"), gvisor works.
            tun["stack"] = "gvisor"
        }
        return tun
    }

    /// SFM can't read Neon Pup's bundle, so it downloads sing-box's published lists through Claude's roads
    /// (never direct) and keeps them in its cache.
    static func ruleSets(_ platform: RuntimeOptions.Platform, resources: String) -> [[String: Any]] {
        switch platform {
        case .helper:
            return [["tag": "geoip-cn", "type": "local", "format": "binary", "path": resources + "/geoip-cn.srs"],
                    ["tag": "geosite-cn", "type": "local", "format": "binary", "path": resources + "/geosite-cn.srs"]]
        case .sfm:
            let base = "https://raw.githubusercontent.com/SagerNet"
            let client: [String: Any] = ["detour": "claude"]
            return [["tag": "geoip-cn", "type": "remote", "format": "binary", "url": base + "/sing-geoip/rule-set/geoip-cn.srs",
                     "http_client": client, "update_interval": "7d"],
                    ["tag": "geosite-cn", "type": "remote", "format": "binary", "url": base + "/sing-geosite/rule-set/geosite-cn.srs",
                     "http_client": client, "update_interval": "7d"]]
        }
    }

    static func experimental(_ options: RuntimeOptions) -> [String: Any] {
        var e: [String: Any] = ["clash_api": ["external_controller": "127.0.0.1:\(options.apiPort)",
                                              "secret": options.apiSecret, "default_mode": "Rule"]]
        if options.platform == .sfm { e["cache_file"] = ["enabled": true] }
        return e
    }

    static func outbound(_ r: RoadSpec, tag: String) -> [String: Any] {
        var o: [String: Any] = ["tag": tag, "server": r.host, "domain_resolver": "local-dns"]
        switch r.kind {
        case .reality:
            o["type"] = "vless"; o["server_port"] = r.port; o["uuid"] = r.uuid ?? ""; o["flow"] = "xtls-rprx-vision"
            o["tls"] = ["enabled": true, "server_name": r.serverName ?? "",
                        "utls": ["enabled": true, "fingerprint": r.fingerprint ?? "chrome"],
                        "reality": ["enabled": true, "public_key": r.publicKey ?? "", "short_id": r.shortID ?? ""]]
        case .websocket:
            o["type"] = "vless"; o["server_port"] = r.port; o["uuid"] = r.uuid ?? ""
            o["tls"] = ["enabled": true, "server_name": r.serverName ?? r.host]
            var transport: [String: Any] = ["type": "ws", "path": r.path ?? "/"]
            if let h = r.wsHost { transport["headers"] = ["Host": h] }
            o["transport"] = transport
        case .hysteria2:
            o["type"] = "hysteria2"; o["password"] = r.password ?? ""
            if let from = r.hopFrom, let to = r.hopTo {
                o["server_ports"] = ["\(from):\(to)"]; o["hop_interval"] = "30s"
            } else {
                o["server_port"] = r.port
            }
            if let obfs = r.obfsPassword { o["obfs"] = ["type": "salamander", "password": obfs] }
            var tls: [String: Any] = ["enabled": true, "server_name": r.serverName ?? r.host]
            if let pin = r.publicKeySHA256 { tls["certificate_public_key_sha256"] = [pin] }
            else if r.allowInsecure { tls["insecure"] = true }
            o["tls"] = tls
        }
        return o
    }
}

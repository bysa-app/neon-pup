import Foundation

public struct RuntimeOptions: Sendable {
    public let resourcesPath: String
    public let apiPort: Int
    public let apiSecret: String
    public init(resourcesPath: String, apiPort: Int, apiSecret: String) {
        self.resourcesPath = resourcesPath
        self.apiPort = apiPort
        self.apiSecret = apiSecret
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
                    ["rule_set": "geosite-cn", "action": "route", "server": "local-dns"],
                ],
                "final": "proxy-dns",
            ],
            "inbounds": [[
                "tag": "tun-in", "type": "tun", "interface_name": tunnelName,
                "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
                "auto_route": true, "strict_route": true, "stack": "mixed",
            ]],
            "outbounds": outbounds,
            "route": [
                "default_domain_resolver": "local-dns",
                "rules": [
                    ["action": "sniff"],
                    ["protocol": "dns", "action": "hijack-dns"],
                    ["domain_suffix": claudeDomains, "action": "route", "outbound": "claude"],
                    ["clash_mode": "Direct", "action": "route", "outbound": "direct"],
                    ["ip_is_private": true, "action": "route", "outbound": "direct"],
                    ["rule_set": "geoip-cn", "action": "route", "outbound": "direct"],
                    ["rule_set": "geosite-cn", "action": "route", "outbound": "direct"],
                ],
                "rule_set": [
                    ["tag": "geoip-cn", "type": "local", "format": "binary", "path": resources + "/geoip-cn.srs"],
                    ["tag": "geosite-cn", "type": "local", "format": "binary", "path": resources + "/geosite-cn.srs"],
                ],
                "final": "choice",
                "auto_detect_interface": true,
            ],
            "experimental": ["clash_api": [
                "external_controller": "127.0.0.1:\(options.apiPort)",
                "secret": options.apiSecret,
                "default_mode": "Rule",
            ]],
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
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

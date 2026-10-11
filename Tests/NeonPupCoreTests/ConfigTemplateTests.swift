import XCTest
@testable import NeonPupCore

/// Own roads: the helper builds the whole engine config from checked RoadSpecs. User values only ever
/// land in value positions; the structure keeps every protection the old ConfigBuilder had.
final class ConfigTemplateTests: XCTestCase {
    let roads = [RoadValidatorTests.reality, RoadValidatorTests.hy2, RoadValidatorTests.ws]
    let options = RuntimeOptions(resourcesPath: "/Applications/Neon Pup.app/Contents/Resources", apiPort: 23456, apiSecret: "s")

    func built(_ roads: [RoadSpec]? = nil) throws -> [String: Any] {
        let data = try ConfigTemplate.build(roads: roads ?? self.roads, options: options)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    func outbound(_ root: [String: Any], _ tag: String) -> [String: Any]? {
        (root["outbounds"] as? [[String: Any]])?.first { $0["tag"] as? String == tag }
    }

    func testTagsFollowTheUsersOrder() throws {
        let root = try built()
        XCTAssertEqual(outbound(root, "claude")?["outbounds"] as? [String], ["road-1", "road-2", "road-3"])
        XCTAssertEqual(outbound(root, "claude")?["default"] as? String, "road-1")
        XCTAssertEqual(outbound(root, "choice")?["outbounds"] as? [String], ["auto", "road-1", "road-2", "road-3"])
        XCTAssertEqual(outbound(root, "auto")?["type"] as? String, "urltest")
        XCTAssertEqual(ConfigTemplate.tags(count: 3), ["road-1", "road-2", "road-3"])
    }

    /// SFM runs the engine inside Apple's NetworkExtension (2026-10-10): macOS owns the tunnel and its DNS, so
    /// the profile leaves the tunnel to it, fetches the China lists through Claude's roads (SFM can't read
    /// Neon Pup's bundle) and keeps Neon Pup's control port. Everything else is the same config.
    func testSFMProfileLeavesTheTunnelToMacOS() throws {
        let sfm = RuntimeOptions(resourcesPath: "", apiPort: 47321, apiSecret: "s", platform: .sfm)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: ConfigTemplate.build(roads: roads, options: sfm)) as? [String: Any])
        let tun = try XCTUnwrap((root["inbounds"] as? [[String: Any]])?.first)
        XCTAssertEqual(tun["type"] as? String, "tun")
        XCTAssertNil(tun["interface_name"], "macOS names the interface")
        // Measured 2026-10-10: without auto_route NetworkExtension gets no routes; the default stack can't bind.
        XCTAssertEqual(tun["auto_route"] as? Bool, true)
        XCTAssertEqual(tun["stack"] as? String, "gvisor")
        let route = try XCTUnwrap(root["route"] as? [String: Any])
        let sets = try XCTUnwrap(route["rule_set"] as? [[String: Any]])
        XCTAssertEqual(sets.map { $0["type"] as? String }, ["remote", "remote"])
        // sing-box 1.14: download_detour is deprecated (SFM shows a warning popup); http_client.detour replaces it.
        XCTAssertTrue(sets.allSatisfy { $0["download_detour"] == nil })
        XCTAssertEqual(Set(sets.compactMap { ($0["http_client"] as? [String: Any])?["detour"] as? String }), ["claude"])
        XCTAssertTrue(sets.allSatisfy { ($0["url"] as? String)?.hasPrefix("https://") == true })
        let exp = try XCTUnwrap(root["experimental"] as? [String: Any])
        XCTAssertEqual((exp["clash_api"] as? [String: Any])?["external_controller"] as? String, "127.0.0.1:47321")
        XCTAssertEqual((exp["cache_file"] as? [String: Any])?["enabled"] as? Bool, true)
        // Claude's pin is unchanged.
        XCTAssertEqual(outbound(root, "claude")?["outbounds"] as? [String], ["road-1", "road-2", "road-3"])
    }

    /// Neon Pup proves SFM runs the current server list: the profile carries a fingerprint outbound that the
    /// control API lists. Same servers, same fingerprint; any change, a new one.
    func testProfileCarriesAServerListFingerprint() throws {
        let sfm = RuntimeOptions(resourcesPath: "", apiPort: 47321, apiSecret: "s", platform: .sfm)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: ConfigTemplate.build(roads: roads, options: sfm)) as? [String: Any])
        let print = ConfigTemplate.fingerprintTag(roads: roads)
        XCTAssertTrue(print.hasPrefix("np-"))
        XCTAssertNotNil(outbound(root, print))
        XCTAssertEqual(print, ConfigTemplate.fingerprintTag(roads: roads))
        XCTAssertNotEqual(print, ConfigTemplate.fingerprintTag(roads: Array(roads.reversed())))
        var renamed = roads; renamed[0].name = "Other name"
        XCTAssertNotEqual(print, ConfigTemplate.fingerprintTag(roads: renamed), "names show in the panel too")
    }

    /// "Tunnel Chinese sites too" is a live switch (engine mode), not a new profile: China lists send traffic and
    /// lookups direct only in the normal mode; in "Global" everything but the hotel window goes to the servers.
    func testChinaRulesOnlyApplyInTheNormalMode() throws {
        let root = try built()
        let route = try XCTUnwrap(root["route"] as? [String: Any])
        let rules = try XCTUnwrap(route["rules"] as? [[String: Any]])
        let china = rules.filter { ($0["rule_set"] as? String)?.hasSuffix("-cn") == true }
        XCTAssertEqual(china.count, 2)
        XCTAssertTrue(china.allSatisfy { $0["clash_mode"] as? String == "Rule" })
        let dnsRules = try XCTUnwrap((root["dns"] as? [String: Any])?["rules"] as? [[String: Any]])
        let chinaDNS = try XCTUnwrap(dnsRules.first { $0["rule_set"] as? String == "geosite-cn" })
        XCTAssertEqual(chinaDNS["clash_mode"] as? String, "Rule")
        // Claude stays first, before the hotel and China exceptions.
        XCTAssertEqual(rules.firstIndex { ($0["outbound"] as? String) == "claude" }, 2)
    }

    func testRoadOutbounds() throws {
        let root = try built()
        let r = try XCTUnwrap(outbound(root, "road-1"))
        XCTAssertEqual(r["type"] as? String, "vless"); XCTAssertEqual(r["flow"] as? String, "xtls-rprx-vision")
        let tls = try XCTUnwrap(r["tls"] as? [String: Any])
        XCTAssertEqual((tls["reality"] as? [String: Any])?["public_key"] as? String, RoadValidatorTests.reality.publicKey)
        let h = try XCTUnwrap(outbound(root, "road-2"))
        XCTAssertEqual(h["server_ports"] as? [String], ["20000:50000"])
        XCTAssertEqual((h["obfs"] as? [String: Any])?["type"] as? String, "salamander")
        XCTAssertEqual((h["tls"] as? [String: Any])?["certificate_public_key_sha256"] as? [String], [RoadValidatorTests.hy2.publicKeySHA256!])
        XCTAssertNil((h["tls"] as? [String: Any])?["insecure"], "a pinned road never skips the check")
        let w = try XCTUnwrap(outbound(root, "road-3"))
        XCTAssertEqual((w["transport"] as? [String: Any])?["path"] as? String, "/abc123")
    }

    func testUnpinnedHysteriaSkipsTheCheckOnlyWhenTheLinkSaysSo() throws {
        var unpinned = RoadValidatorTests.hy2; unpinned.publicKeySHA256 = nil
        let tls = (outbound(try built([unpinned]), "road-1")?["tls"] as? [String: Any])
        XCTAssertEqual(tls?["insecure"] as? Bool, true)
    }

    func testProtectionsStayInPlace() throws {
        let root = try built()
        let tun = try XCTUnwrap((root["inbounds"] as? [[String: Any]])?.first)
        XCTAssertEqual(tun["type"] as? String, "tun"); XCTAssertEqual(tun["interface_name"] as? String, "utun233")
        XCTAssertEqual(tun["strict_route"] as? Bool, true)
        let route = try XCTUnwrap(root["route"] as? [String: Any])
        let rules = try XCTUnwrap(route["rules"] as? [[String: Any]])
        let claude = try XCTUnwrap(rules.firstIndex { $0["outbound"] as? String == "claude" })
        XCTAssertEqual(rules[claude]["domain_suffix"] as? [String], ConfigTemplate.claudeDomains)
        let hotel = try XCTUnwrap(rules.firstIndex { $0["clash_mode"] as? String == "Direct" })
        XCTAssertLessThan(claude, hotel)
        XCTAssertEqual(route["final"] as? String, "choice")
        let dns = try XCTUnwrap(root["dns"] as? [String: Any])
        let dnsRules = try XCTUnwrap(dns["rules"] as? [[String: Any]])
        XCTAssertEqual(dnsRules[0]["server"] as? String, "proxy-dns")
        XCTAssertEqual(dnsRules[1]["server"] as? String, "hotel-dns")
        let servers = try XCTUnwrap(dns["servers"] as? [[String: Any]])
        XCTAssertEqual(servers.first { $0["tag"] as? String == "proxy-dns" }?["detour"] as? String, "claude")
        let sets = try XCTUnwrap(route["rule_set"] as? [[String: Any]])
        XCTAssertEqual(sets.compactMap { $0["path"] as? String }, [options.resourcesPath + "/geoip-cn.srs", options.resourcesPath + "/geosite-cn.srs"])
        let api = try XCTUnwrap((root["experimental"] as? [String: Any])?["clash_api"] as? [String: Any])
        XCTAssertEqual(api["external_controller"] as? String, "127.0.0.1:23456")
    }

    func testRefusesBadInput() {
        var bad = RoadValidatorTests.reality; bad.host = "evil\"host"
        XCTAssertThrowsError(try ConfigTemplate.build(roads: [bad], options: options))
        XCTAssertThrowsError(try ConfigTemplate.build(roads: [], options: options))
        XCTAssertThrowsError(try ConfigTemplate.build(roads: Array(repeating: RoadValidatorTests.reality, count: 9), options: options))
    }

    /// the maintainer's real roads (read at test time, piped to sing-box, never written) must pass sing-box's check.
    func testRealLinksPassSingBoxCheck() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let engine = repo.appendingPathComponent("build/cache/sing-box-universal")
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("github/router/clients/uris")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".txt") }.sorted()) ?? []
        try XCTSkipUnless(FileManager.default.fileExists(atPath: engine.path) && !files.isEmpty, "needs build + rendered links")
        let roads = try files.map { file -> RoadSpec in
            let link = try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)
            return try ShareLinkParser.parse(link).get()
        }
        XCTAssertEqual(roads.count, 5)
        let config = try ConfigTemplate.build(roads: roads, options: RuntimeOptions(
            resourcesPath: NSHomeDirectory() + "/github/router/clients/sarah", apiPort: 9, apiSecret: "x"))
        let p = Process()
        p.executableURL = engine
        p.arguments = ["check", "-c", "/dev/stdin"]
        let input = Pipe(), output = Pipe()
        p.standardInput = input; p.standardOutput = output; p.standardError = output
        try p.run()
        input.fileHandleForWriting.write(config)
        try input.fileHandleForWriting.close()
        p.waitUntilExit()
        let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(p.terminationStatus, 0, LogLine.lastError(in: text) ?? text)
    }
}

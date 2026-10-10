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

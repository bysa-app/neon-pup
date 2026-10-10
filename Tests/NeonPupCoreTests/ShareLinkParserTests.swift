import XCTest
@testable import NeonPupCore

/// Shapes exactly as ~/github/router/clients/render-clients.py writes them (fake values).
final class ShareLinkParserTests: XCTestCase {
    let uuid = "11111111-2222-4333-8444-555555555555"
    let pbk = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    var reality: String { "vless://\(uuid)@192.0.2.10:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.apple.com&fp=chrome&pbk=\(pbk)&sid=0123456789abcdef&type=tcp#SG-Reality" }
    var hy2: String { "hysteria2://p%40ss%2Fw0rd@192.0.2.10:20000-50000/?obfs=salamander&obfs-password=ob%2Bfs&sni=bing.com&insecure=1&pinSHA256=0000000000000000000000000000000000000000000000000000000000000000&pinPublicKey=BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB%3D#SG-Hysteria2" }
    var ws: String { "vless://\(uuid)@proxy.example.com:8443?encryption=none&security=tls&sni=proxy.example.com&type=ws&host=proxy.example.com&path=%2Ffeedfacefeedface#Cloudflare-CDN" }

    func road(_ link: String) throws -> RoadSpec {
        switch ShareLinkParser.parse(link) {
        case .success(let r): return r
        case .failure(let e): XCTFail("\(e.message)"); throw e
        }
    }

    func failure(_ link: String) -> String? {
        if case .failure(let e) = ShareLinkParser.parse(link) { return e.message }
        return nil
    }

    func testReality() throws {
        let r = try road(reality)
        XCTAssertEqual(r.kind, .reality); XCTAssertEqual(r.host, "192.0.2.10"); XCTAssertEqual(r.port, 443)
        XCTAssertEqual(r.uuid, uuid); XCTAssertEqual(r.serverName, "www.apple.com"); XCTAssertEqual(r.publicKey, pbk)
        XCTAssertEqual(r.shortID, "0123456789abcdef"); XCTAssertEqual(r.fingerprint, "chrome"); XCTAssertEqual(r.name, "SG-Reality")
    }

    func testHysteria2WithEncodedSecretsAndHopping() throws {
        let r = try road(hy2)
        XCTAssertEqual(r.kind, .hysteria2); XCTAssertEqual(r.password, "p@ss/w0rd"); XCTAssertEqual(r.obfsPassword, "ob+fs")
        XCTAssertEqual(r.port, 20000); XCTAssertEqual(r.hopFrom, 20000); XCTAssertEqual(r.hopTo, 50000)
        XCTAssertEqual(r.serverName, "bing.com"); XCTAssertTrue(r.allowInsecure)
        XCTAssertEqual(r.publicKeySHA256, "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=")
        XCTAssertFalse(r.isUnpinned)
    }

    func testHysteria2SinglePortAndNoPinIsUnpinned() throws {
        let r = try road("hysteria2://secret@1.2.3.4:443?obfs=salamander&obfs-password=x1&insecure=1#plain")
        XCTAssertEqual(r.port, 443); XCTAssertNil(r.hopFrom); XCTAssertTrue(r.isUnpinned)
    }

    func testWebSocket() throws {
        let r = try road(ws)
        XCTAssertEqual(r.kind, .websocket); XCTAssertEqual(r.path, "/feedfacefeedface"); XCTAssertEqual(r.wsHost, "proxy.example.com")
        XCTAssertEqual(r.port, 8443)
    }

    func testIPv6Host() throws {
        let r = try road(reality.replacingOccurrences(of: "192.0.2.10", with: "[2606:4700::1111]"))
        XCTAssertEqual(r.host, "2606:4700::1111")
    }

    func testUnsupportedLinksSayPlainWords() {
        for link in ["ss://YWVzOnBhc3M=@1.2.3.4:8388#x", "vmess://abc", "https://example.com", "hello", ""] {
            XCTAssertEqual(failure(link), "This link isn't something I understand", link)
        }
        // vless without a supported security mode
        XCTAssertEqual(failure(reality.replacingOccurrences(of: "security=reality", with: "security=none")),
                       "This link isn't something I understand")
        XCTAssertEqual(failure(hy2.replacingOccurrences(of: "obfs=salamander", with: "obfs=other")),
                       "This link isn't something I understand")
    }

    func testBrokenFieldsAreNamed() {
        XCTAssertEqual(failure(reality.replacingOccurrences(of: "pbk=\(pbk)", with: "pbk=short")),
                       "This link has a problem with: key")
        XCTAssertEqual(failure(reality.replacingOccurrences(of: "192.0.2.10", with: "evil\"host")),
                       "This link has a problem with: address")
        XCTAssertEqual(failure(reality.replacingOccurrences(of: ":443", with: ":99999")),
                       "This link has a problem with: port")
    }

    func testNamesAreCleanedNotRejected() throws {
        let r = try road(reality.replacingOccurrences(of: "#SG-Reality", with: "#Tokyo%20%22fast%22%E2%80%AE" + String(repeating: "x", count: 60)))
        XCTAssertEqual(RoadValidator.problems(r), [])
        XCTAssertFalse(r.name.contains("\""))
        XCTAssertLessThanOrEqual(r.name.count, 40)
        let unnamed = try road(reality.replacingOccurrences(of: "#SG-Reality", with: ""))
        XCTAssertEqual(unnamed.name, "Server")
    }

    func testParseAllSplitsLinesAndKeepsOrder() {
        let results = ShareLinkParser.parseAll("\n  \(reality)  \nnonsense\n\(ws)\n")
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results.map(\.line), [reality, "nonsense", ws])
        XCTAssertNotNil(try? results[0].result.get())
        XCTAssertNil(try? results[1].result.get())
    }
}

/// Security review 2026-10-10: a certificate pin we cannot enforce must not be silently dropped.
final class ShareLinkPinDowngradeTests: XCTestCase {
    func testCertificatePinWithoutAPublicKeyPinIsRefused() {
        let link = "hysteria2://secret@1.2.3.4:443?obfs=salamander&obfs-password=x1&insecure=1&pinSHA256=0000000000000000000000000000000000000000000000000000000000000000#pinned"
        guard case .failure(let e) = ShareLinkParser.parse(link) else { return XCTFail("must not downgrade silently") }
        XCTAssertEqual(e.message, "This link locks to a safety key I can't check. Ask for a newer link")
    }
}

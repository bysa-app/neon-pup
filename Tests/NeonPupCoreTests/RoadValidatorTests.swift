import XCTest
@testable import NeonPupCore

/// Own roads (2026-10-10): every field from a pasted link is checked in the app AND the helper.
final class RoadValidatorTests: XCTestCase {
    static let reality = RoadSpec(kind: .reality, name: "Singapore everyday", host: "192.0.2.10", port: 443,
                                  uuid: "11111111-2222-4333-8444-555555555555", serverName: "www.apple.com",
                                  publicKey: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", shortID: "0123456789abcdef",
                                  fingerprint: "chrome")
    static let ws = RoadSpec(kind: .websocket, name: "Secret tunnel", host: "proxy.example.com", port: 8443,
                             uuid: "11111111-2222-4333-8444-555555555555", serverName: "proxy.example.com",
                             path: "/abc123", wsHost: "proxy.example.com")
    static let hy2 = RoadSpec(kind: .hysteria2, name: "Singapore turbo", host: "192.0.2.10", port: 443,
                              hopFrom: 20000, hopTo: 50000, password: "pa55word", serverName: "bing.com",
                              obfsPassword: "obfs-pass", publicKeySHA256: "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=",
                              allowInsecure: true)

    func testGoodRoadsPass() {
        for road in [Self.reality, Self.ws, Self.hy2] { XCTAssertEqual(RoadValidator.problems(road), [], road.name) }
    }

    func testHostsAndPorts() {
        for host in ["a.b", "192.0.2.10", "2606:4700::1111", "proxy-1.example.co"] {
            var r = Self.reality; r.host = host
            XCTAssertEqual(RoadValidator.problems(r), [], host)
        }
        for host in ["", "a b", "evil\"host", "host\nx", "-.x", "a..b", String(repeating: "a", count: 300), "ex\u{0430}mple.com"] {
            var r = Self.reality; r.host = host
            XCTAssertTrue(RoadValidator.problems(r).contains("address"), host)
        }
        for port in [0, 65536, -1] { var r = Self.reality; r.port = port; XCTAssertTrue(RoadValidator.problems(r).contains("port")) }
        var r = Self.hy2; r.hopFrom = 50000; r.hopTo = 20000
        XCTAssertTrue(RoadValidator.problems(r).contains("port range"))
    }

    func testRealityFields() {
        var r = Self.reality; r.uuid = "not-a-uuid"
        XCTAssertTrue(RoadValidator.problems(r).contains("user id"))
        r = Self.reality; r.publicKey = "short"
        XCTAssertTrue(RoadValidator.problems(r).contains("key"))
        r = Self.reality; r.shortID = "xyz"
        XCTAssertTrue(RoadValidator.problems(r).contains("short id"))
        r = Self.reality; r.fingerprint = "hacker"
        XCTAssertTrue(RoadValidator.problems(r).contains("fingerprint"))
        r = Self.reality; r.serverName = nil
        XCTAssertTrue(RoadValidator.problems(r).contains("disguise name"))
    }

    func testWebSocketPath() {
        for bad in ["abc", "/a b", "/a\"b", "/" + String(repeating: "a", count: 200)] {
            var r = Self.ws; r.path = bad
            XCTAssertTrue(RoadValidator.problems(r).contains("path"), bad)
        }
    }

    func testHysteria2Secrets() {
        for bad in ["", "has\"quote", "back\\slash", "new\nline", String(repeating: "x", count: 200)] {
            var r = Self.hy2; r.password = bad
            XCTAssertTrue(RoadValidator.problems(r).contains("password"), bad)
        }
        var r = Self.hy2; r.publicKeySHA256 = "zz"
        XCTAssertTrue(RoadValidator.problems(r).contains("pin"))
        r = Self.hy2; r.publicKeySHA256 = nil; r.allowInsecure = false
        XCTAssertEqual(RoadValidator.problems(r), [], "a real certificate needs no pin")
    }

    func testNames() {
        for bad in ["", String(repeating: "a", count: 41), "tab\there", "quote\"", "\u{202E}rtl"] {
            var r = Self.reality; r.name = bad
            XCTAssertTrue(RoadValidator.problems(r).contains("name"), bad)
        }
        var r = Self.reality; r.name = "Singapore, everyday road (fast)"
        XCTAssertEqual(RoadValidator.problems(r), [])
    }

    func testFieldsThatDoNotBelongToTheKindAreRefused() {
        var r = Self.reality; r.path = "/x"
        XCTAssertTrue(RoadValidator.problems(r).contains("extra fields"))
    }
}

/// Security review 2026-10-10: ICU "$" also matches before a trailing newline; anchors must be strict.
final class RoadValidatorAnchorTests: XCTestCase {
    func testTrailingNewlinesAreRefusedEverywhere() {
        var r = RoadValidatorTests.reality; r.host = "a.b\n"
        XCTAssertTrue(RoadValidator.problems(r).contains("address"))
        r = RoadValidatorTests.reality; r.uuid = (r.uuid ?? "") + "\n"
        XCTAssertTrue(RoadValidator.problems(r).contains("user id"))
        r = RoadValidatorTests.reality; r.publicKey = (r.publicKey ?? "") + "\n"
        XCTAssertTrue(RoadValidator.problems(r).contains("key"))
        r = RoadValidatorTests.reality; r.serverName = "www.apple.com\n"
        XCTAssertTrue(RoadValidator.problems(r).contains("disguise name"))
        var w = RoadValidatorTests.ws; w.path = "/abc\n"
        XCTAssertTrue(RoadValidator.problems(w).contains("path"))
        var h = RoadValidatorTests.hy2; h.publicKeySHA256 = (h.publicKeySHA256 ?? "") + "\n"
        XCTAssertTrue(RoadValidator.problems(h).contains("pin"))
        r = RoadValidatorTests.reality; r.host = "2606:4700::1\n"
        XCTAssertTrue(RoadValidator.problems(r).contains("address"))
    }

    func testWebSocketRefusesAFingerprint() {
        var w = RoadValidatorTests.ws; w.fingerprint = "chrome"
        XCTAssertTrue(RoadValidator.problems(w).contains("extra fields"))
    }
}

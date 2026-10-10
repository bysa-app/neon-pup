import XCTest
@testable import NeonPupCore

/// the maintainer 2026-10-10: a report people can paste into Claude, with the engine's recent log.
final class LogExportTests: XCTestCase {
    func testRingKeepsTheLastLinesWithoutColourCodes() {
        var ring = LogRing(capacity: 3)
        ring.append("\u{1B}[31mERROR\u{1B}[0m one\nWARN two\n")
        ring.append("three\nfour\n")
        XCTAssertEqual(ring.lines, ["WARN two", "three", "four"])
    }

    func testRingJoinsLinesSplitAcrossReads() {
        var ring = LogRing(capacity: 10)
        ring.append("first half")
        ring.append(" second half\nnext\n")
        XCTAssertEqual(ring.lines, ["first half second half", "next"])
    }

    func testReportCarriesClaudeIntroLogAndHidesSecretsAndHosts() {
        let road = RoadSpec(kind: .hysteria2, name: "Home", host: "203.0.113.77", port: 443, password: "hunter2-pass")
        let facts = DiagnosticFacts(appVersion: "1.0", macOSVersion: "26.2", cpu: "apple silicon", phase: "connected",
                                    mode: "secure", pickedRoad: nil, roadDelays: [:], lastError: nil, helper: "ready")
        let log = "ERROR dial 203.0.113.77:443 with hunter2-pass failed"
        let text = Diagnostics.report(facts, roads: Roads.from([road]), log: log,
                                      redacting: Diagnostics.secrets(from: [road]))
        XCTAssertTrue(text.hasPrefix(Diagnostics.claudeIntro))
        XCTAssertTrue(text.contains("ERROR dial <hidden>:443 with <hidden> failed"))
        XCTAssertFalse(text.contains("203.0.113.77"))
        XCTAssertFalse(text.contains("hunter2-pass"))
    }

    /// Security review 2026-10-10 (round 2): secrets go first, so masking cannot split a secret that holds
    /// something IP-shaped, and hosts match whatever case the log prints them in.
    func testSecretsAreHiddenBeforeMaskingAndHostsIgnoreCase() {
        let road = RoadSpec(kind: .hysteria2, name: "Home", host: "Home.Example.NET", port: 443, password: "pw-10.0.0.1-secret")
        let facts = DiagnosticFacts(appVersion: "1.0", macOSVersion: "26.2", cpu: "apple silicon", phase: "connected",
                                    mode: "secure", pickedRoad: nil, roadDelays: [:], lastError: nil, helper: "ready")
        let log = "ERROR auth pw-10.0.0.1-secret rejected by home.example.net"
        let text = Diagnostics.report(facts, roads: Roads.from([road]), log: log,
                                      redacting: Diagnostics.secrets(from: [road]))
        XCTAssertFalse(text.contains("secret rejected"), "the end of the password leaked")
        XCTAssertFalse(text.lowercased().contains("example.net"))
        XCTAssertTrue(text.contains("ERROR auth <hidden> rejected by <hidden>"))
    }

    /// Security review 2026-10-10: a server given as a domain shows up in the log by its resolved address,
    /// which the per-link list cannot know. Every IP address in the log is masked.
    func testResolvedAddressesInTheLogAreMasked() {
        let road = RoadSpec(kind: .hysteria2, name: "Home", host: "home.example.net", port: 443, password: "hunter2-pass")
        let facts = DiagnosticFacts(appVersion: "1.0", macOSVersion: "26.2", cpu: "apple silicon", phase: "connected",
                                    mode: "secure", pickedRoad: nil, roadDelays: [:], lastError: nil, helper: "ready")
        let log = "+0800 2026-10-10 12:34:56 ERROR dial tcp 198.51.100.23:443: timeout\n"
            + "WARN udp [2001:db8::42]:443 refused\nWARN full 2001:0db8:0000:0000:0000:0000:0000:0042\nversion 1.13.7"
        let text = Diagnostics.report(facts, roads: Roads.from([road]), log: log,
                                      redacting: Diagnostics.secrets(from: [road]))
        XCTAssertFalse(text.contains("198.51.100.23"))
        XCTAssertFalse(text.contains("2001:db8::42"))
        XCTAssertFalse(text.contains("2001:0db8"))
        XCTAssertTrue(text.contains("dial tcp <address>:443: timeout"))
        XCTAssertTrue(text.contains("12:34:56"), "times are not addresses")
        XCTAssertTrue(text.contains("version 1.13.7"), "version numbers are not addresses")
    }
}

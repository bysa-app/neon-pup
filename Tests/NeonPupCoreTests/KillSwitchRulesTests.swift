import XCTest
@testable import NeonPupCore

/// Kill switch ("seal"), applied by the helper whenever it is wanted and the engine is NOT running
/// (connecting, engine died, napping in China mode). While the engine runs, the tunnel's strict routing
/// captures all traffic, so the seal is lifted and the engine can reach its servers.
/// Live drill 2026-10-10: pf did not attribute the engine's TCP to uid 0, so no exemption is relied on.
final class KillSwitchRulesTests: XCTestCase {
    var lines: [String] {
        KillSwitchRules.sealed.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("#") && !$0.isEmpty }
    }

    func testEverythingOutIsBlockedLast() {
        XCTAssertEqual(lines.last, "block drop out quick all")
        XCTAssertTrue(lines.allSatisfy { $0.contains("quick") })
    }

    func testOnlyLoopbackAndLocalNetworkGetThrough() {
        let block = lines.firstIndex(of: "block drop out quick all")!
        for needle in ["on lo0", "192.168.0.0/16", "fe80::/10"] {
            XCTAssertLessThan(lines.firstIndex { $0.contains(needle) }!, block, needle)
        }
        XCTAssertFalse(lines.contains { $0.contains("user") }, "no per-program exemptions")
        XCTAssertFalse(lines.contains { $0.contains("utun") }, "nothing is tunnelled while sealed")
    }

    /// A sealed Mac must not ask the hotel's DNS server for claude.ai either.
    func testDnsToTheLocalNetworkIsBlocked() {
        let dns = lines.firstIndex(of: "block drop out quick proto { tcp udp } to any port 53")!
        XCTAssertLessThan(dns, lines.firstIndex { $0.contains("192.168.0.0/16") }!)
    }
}

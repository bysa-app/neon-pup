import XCTest
import NeonPupCore

/// Codex review #4 (2026-10-10): the helper lifts the seal only when real `route get` output says the tunnel
/// carries the traffic. Outputs below are copied from this Mac's /sbin/route.
final class RouteCheckTests: XCTestCase {
    let tunnel = "utun233"
    func out(_ iface: String) -> String {
        "   route to: 1.1.1.1\ndestination: default\n       mask: default\n  interface: \(iface)\n      flags: <UP,DONE>\n"
    }

    func testEveryProbeMustGoThroughTheTunnel() {
        XCTAssertTrue(RouteCheck.v4Carried(RouteCheck.v4Probes.map { _ in out(tunnel) }, tunnel: tunnel))
        // Host routes for one or two addresses into the tunnel, everything else direct: refused.
        var outputs = RouteCheck.v4Probes.map { _ in out("en0") }
        outputs[0] = out(tunnel)
        outputs[1] = out(tunnel)
        XCTAssertFalse(RouteCheck.v4Carried(outputs, tunnel: tunnel))
    }

    func testProbesAreSpreadAndIncludeClaude() {
        XCTAssertGreaterThanOrEqual(RouteCheck.v4Probes.count, 4)
        XCTAssertTrue(RouteCheck.v4Probes.contains { $0.hasPrefix("160.79.104.") })
        XCTAssertTrue(RouteCheck.v6Probes.contains { $0.hasPrefix("2607:6bc0:") })
    }

    func testNoOutputOrNoInterfaceIsRefused() {
        XCTAssertFalse(RouteCheck.v4Carried([], tunnel: tunnel))
        XCTAssertFalse(RouteCheck.v4Carried(["route: bad interface name"], tunnel: tunnel))
        XCTAssertFalse(RouteCheck.v4Carried([out("utun2330")], tunnel: tunnel))
    }

    func testIPv6AbsentOnlyWhenRouteSaysNotInTable() {
        XCTAssertTrue(RouteCheck.v6CarriedOrAbsent(["route: writing to routing socket: not in table"], tunnel: tunnel))
        XCTAssertTrue(RouteCheck.v6CarriedOrAbsent([out(tunnel), out(tunnel)], tunnel: tunnel))
        XCTAssertFalse(RouteCheck.v6CarriedOrAbsent([out("en0")], tunnel: tunnel))
        // A command that failed some other way is not proof of "no IPv6 route".
        XCTAssertFalse(RouteCheck.v6CarriedOrAbsent(["route: bad interface name"], tunnel: tunnel))
        XCTAssertFalse(RouteCheck.v6CarriedOrAbsent([""], tunnel: tunnel))
        XCTAssertFalse(RouteCheck.v6CarriedOrAbsent([], tunnel: tunnel))
    }
}

/// Drill 2026-10-10: pfctl prints ALTQ notices even for an empty anchor; they are not rules.
final class AnchorEmptyTests: XCTestCase {
    func testALTQNoticesAreNotRules() {
        XCTAssertTrue(KillSwitchRules.anchorIsEmpty("No ALTQ support in kernel\nALTQ related functions disabled\n"))
        XCTAssertTrue(KillSwitchRules.anchorIsEmpty(""))
        XCTAssertFalse(KillSwitchRules.anchorIsEmpty("No ALTQ support in kernel\nblock drop out all\n"))
        XCTAssertFalse(KillSwitchRules.anchorIsEmpty("pass out quick on lo0 all flags S/SA keep state\n"))
    }
}

import XCTest
import NeonPupCore

/// Neon Pup runs on SFM (sing-box's NetworkExtension app, 2026-10-10). These parse what macOS prints about it.
/// Fixtures are the real output captured on the owner's Mac.
final class SFMStatusTests: XCTestCase {
    let waiting = """
    1 extension(s)
    --- com.apple.system_extension.network_extension
    enabled\tactive\tteamID\tbundleID (version)\tname\t[state]
    \t*\tP8XK3KHB48\tio.nekohasekai.sfamt.system (1.14.3/1)\tSFMExtension\t[activated waiting for user]
    """
    let enabled = """
    --- com.apple.system_extension.network_extension
    enabled\tactive\tteamID\tbundleID (version)\tname\t[state]
    *\t*\tW5W395V82Y\tcom.nordvpn.macos.Shield (10.12.0/377)\tNordVPN protection\t[activated enabled]
    *\t*\tP8XK3KHB48\tio.nekohasekai.sfamt.system (1.14.3/1)\tSFMExtension\t[activated enabled]
    """
    let impostor = """
    *\t*\tABCDEFGHIJ\tio.nekohasekai.sfamt.system (1.14.3/1)\tSFMExtension\t[activated enabled]
    """

    func testExtensionStates() {
        XCTAssertEqual(SFMStatus.extensionState(""), .missing)
        XCTAssertEqual(SFMStatus.extensionState(waiting), .waitingForUser)
        XCTAssertEqual(SFMStatus.extensionState(enabled), .enabled)
        XCTAssertEqual(SFMStatus.extensionState(impostor), .missing, "only SFM's own team counts")
    }

    let list = """
    Available network connection services in the current set (*=enabled):
    * (Connected)      2D7E769E-F522-4E64-B99B-1C1C6F7FBAB7 VPN (io.nekohasekai.sfamt.standalone) "SFM"                            [VPN:io.nekohasekai.sfamt.standalone]
    * (Disconnected)   11111111-2222-3333-4444-555555555555 VPN (com.example.other) "SFM"   [VPN:com.example.other]
    """

    func testVPNServiceIsFoundByProviderNotName() {
        XCTAssertEqual(SFMStatus.vpnService(list), "2D7E769E-F522-4E64-B99B-1C1C6F7FBAB7")
        XCTAssertNil(SFMStatus.vpnService("Available network connection services in the current set (*=enabled):\n"))
        XCTAssertNil(SFMStatus.vpnService("* (Connected) 2D7E769E-F522-4E64-B99B-1C1C6F7FBAB7 VPN (x) \"SFM\" [VPN:com.example.other]"))
    }

    func testConnectionStatus() {
        XCTAssertEqual(SFMStatus.connection("Connected\nExtended Status <dictionary> {"), .connected)
        XCTAssertEqual(SFMStatus.connection("Connecting\n"), .connecting)
        XCTAssertEqual(SFMStatus.connection("Disconnected\n"), .disconnected)
        XCTAssertEqual(SFMStatus.connection("Disconnecting\n"), .disconnecting)
        XCTAssertEqual(SFMStatus.connection("No service\n"), .unknown)
    }

    func testOnlySFMsOwnRequirementIsTrusted() {
        XCTAssertTrue(SFMStatus.appRequirement.contains("P8XK3KHB48"))
        XCTAssertTrue(SFMStatus.appRequirement.contains("io.nekohasekai.sfamt.standalone"))
    }
}

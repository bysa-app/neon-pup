import XCTest
@testable import NeonPupCore

final class AppStateMachineTests: XCTestCase {
    typealias M = AppStateMachine

    func testHappyPath() {
        var p = Phase.off
        p = M.reduce(p, .wakeTapped); XCTAssertEqual(p, .connecting)
        p = M.reduce(p, .engineReady); XCTAssertEqual(p, .connected)
        p = M.reduce(p, .roadPicked); XCTAssertEqual(p, .switching)
        p = M.reduce(p, .roadsBack); XCTAssertEqual(p, .connected)
        p = M.reduce(p, .napTapped); XCTAssertEqual(p, .off)
    }

    func testTroubleKinds() {
        XCTAssertEqual(M.reduce(.connected, .pickedRoadUnreachable), .trouble(.roadClosed))
        XCTAssertEqual(M.reduce(.connected, .allRoadsDown(directInternet: true)), .trouble(.allRoadsSleepy))
        XCTAssertEqual(M.reduce(.connected, .allRoadsDown(directInternet: false)), .trouble(.noInternet))
        XCTAssertEqual(M.reduce(.trouble(.noInternet), .roadsBack), .connected)
        XCTAssertEqual(M.reduce(.connecting, .engineFailed), .failed)
        XCTAssertEqual(M.reduce(.connecting, .helperNeedsApproval), .trouble(.needsApproval))
    }

    func testEventsWhileOffDoNothing() {
        for e in [Event.engineReady, .roadPicked, .pickedRoadUnreachable, .allRoadsDown(directInternet: true), .roadsBack, .engineFailed] {
            XCTAssertEqual(M.reduce(.off, e), .off, "\(e)")
        }
    }

    func testWakeOnlyFromRestingStates() {
        XCTAssertEqual(M.reduce(.failed, .wakeTapped), .connecting)
        XCTAssertEqual(M.reduce(.trouble(.needsApproval), .wakeTapped), .connecting)
        XCTAssertEqual(M.reduce(.connected, .wakeTapped), .connected)
        XCTAssertEqual(M.reduce(.connecting, .wakeTapped), .connecting)
    }

    func testCopyAndMood() {
        XCTAssertEqual(M.status(.connected, mode: .secure), "Connected, cozy and safe")
        XCTAssertEqual(M.status(.connecting), "Sniffing for a server...")
        XCTAssertEqual(M.status(.trouble(.roadClosed)), "This server is blocked here, trying another")
        XCTAssertEqual(M.status(.trouble(.allRoadsSleepy)), "All servers are sleepy, I'll keep trying")
        XCTAssertEqual(M.status(.trouble(.noInternet)), "No internet at all, check the Wi-Fi")
        XCTAssertEqual(M.status(.failed), "The connection dropped. Press Wake me up to try again")
        XCTAssertEqual(M.buttonTitle(.off), "Wake me up")
        XCTAssertEqual(M.buttonTitle(.failed), "Wake me up")
        XCTAssertEqual(M.buttonTitle(.trouble(.needsApproval)), "Wake me up")
        XCTAssertEqual(M.buttonTitle(.connected), "Let me nap")
        XCTAssertEqual(M.mood(.off), .sleeping)
        XCTAssertEqual(M.mood(.connecting), .sniffing)
        XCTAssertEqual(M.mood(.connected), .happy)
        XCTAssertEqual(M.mood(.trouble(.noInternet)), .confused)
        XCTAssertEqual(M.mood(.failed), .confused)
        XCTAssertFalse(M.isOn(.off)); XCTAssertFalse(M.isOn(.failed)); XCTAssertFalse(M.isOn(.trouble(.needsApproval)))
        XCTAssertTrue(M.isOn(.connected)); XCTAssertTrue(M.isOn(.trouble(.noInternet)))
    }

    func testNoJargonInAnyStatus() {
        let all: [Phase] = [.off, .connecting, .connected, .switching, .failed,
                            .trouble(.roadClosed), .trouble(.allRoadsSleepy), .trouble(.noInternet), .trouble(.needsApproval)]
        for p in all {
            for word in ["proxy", "vpn", "tun", "protocol", "error"] {
                XCTAssertFalse(M.status(p).lowercased().contains(word), "\(p): \(M.status(p))")
            }
        }
    }
}

/// Extension 2026-10-10: modes, kill switch, hotel login, other VPN app.
final class AppStateMachineExtensionTests: XCTestCase {
    typealias M = AppStateMachine

    func testConnectedWordingFollowsMode() {
        XCTAssertEqual(M.status(.connected, mode: .secure), "Connected, cozy and safe")
        XCTAssertEqual(M.status(.connected, mode: .fast), "Connected, fast and cozy")
        XCTAssertEqual(M.status(.connected, mode: .manual), "Connected on your server")
    }

    func testEngineDeathUnderKillSwitchExplainsThePause() {
        XCTAssertEqual(M.status(.failed, mode: .secure),
                       "The connection dropped. Press Wake me up to try again")
    }

    func testHotelLogin() {
        XCTAssertEqual(M.reduce(.connected, .hotelLoginStarted), .hotelLogin)
        XCTAssertEqual(M.reduce(.hotelLogin, .hotelLoginEnded), .connecting)
        XCTAssertEqual(M.reduce(.hotelLogin, .roadsBack), .hotelLogin, "checks must not end the login window")
        XCTAssertTrue(M.isOn(.hotelLogin))
        XCTAssertEqual(M.status(.hotelLogin, mode: .secure), "Log in on the page that opened. I'll close it once you're online")
        XCTAssertEqual(M.buttonTitle(.hotelLogin), "Done")
    }

    func testOtherVpnBlocksWaking() {
        XCTAssertEqual(M.reduce(.connecting, .otherVPNFound), .trouble(.otherVPN))
        XCTAssertFalse(M.isOn(.trouble(.otherVPN)))
        XCTAssertEqual(M.reduce(.trouble(.otherVPN), .wakeTapped), .connecting)
        XCTAssertEqual(M.status(.trouble(.otherVPN), mode: .secure), "Another app is changing your internet. Quit it, then wake me up")
        XCTAssertEqual(M.buttonTitle(.trouble(.otherVPN)), "Wake me up")
    }

    func testNewCopyHasNoJargon() {
        for p in [Phase.hotelLogin, .failed, .trouble(.otherVPN), .connected] {
            for mode in RoadMode.allCases {
                for word in ["proxy", "vpn", "tun", "protocol", "error", "firewall", "kill switch"] {
                    XCTAssertFalse(M.status(p, mode: mode).lowercased().contains(word), "\(p) \(mode)")
                }
            }
        }
    }
}

/// the maintainer 2026-10-10: in China mode napping means no internet, so the button says so.
final class AppStateMachineChinaModeButtonTests: XCTestCase {
    func testNapButtonSaysGoOfflineInChinaMode() {
        XCTAssertEqual(AppStateMachine.buttonTitle(.connected, chinaMode: true), "Go offline")
        XCTAssertEqual(AppStateMachine.buttonTitle(.connected, chinaMode: false), "Let me nap")
        XCTAssertEqual(AppStateMachine.buttonTitle(.off, chinaMode: true), "Wake me up")
        XCTAssertEqual(AppStateMachine.buttonTitle(.hotelLogin, chinaMode: true), "Done")
    }
}

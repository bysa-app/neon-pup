import Foundation

public enum Trouble: Equatable, Sendable { case roadClosed, allRoadsSleepy, noInternet, needsApproval, otherVPN, notSealed, noRoads }
public enum Phase: Equatable, Sendable { case off, connecting, connected, switching, hotelLogin, trouble(Trouble), failed }
public enum Mood: String, Sendable { case sleeping, sniffing, happy, confused }
public enum Event: Equatable, Sendable {
    case wakeTapped, napTapped, engineReady, roadPicked, pickedRoadUnreachable
    case allRoadsDown(directInternet: Bool)
    case roadsBack, engineFailed, helperNeedsApproval
    case hotelLoginStarted, hotelLoginEnded, otherVPNFound
    /// A seal the Mac needed (China mode, engine down) could not be applied.
    case sealFailed
    case noRoadsFound
}

public enum AppStateMachine {
    /// The hotel login button, only where a Wi-Fi login page cannot appear by itself (the maintainer 2026-10-10):
    /// every road down while on, the Mac blocked ("paused"), or off in China mode. Off outside China mode the
    /// Mac's own pop-up works; while connected there is no login page in the way.
    public static func showsHotelLogin(_ p: Phase, chinaMode: Bool) -> Bool {
        switch p {
        case .off: return chinaMode
        case .failed, .trouble(.allRoadsSleepy), .trouble(.noInternet): return true
        default: return false
        }
    }

    public static func isOn(_ p: Phase) -> Bool {
        switch p {
        case .off, .failed, .trouble(.needsApproval), .trouble(.otherVPN), .trouble(.notSealed), .trouble(.noRoads): return false
        default: return true
        }
    }

    public static func reduce(_ p: Phase, _ e: Event) -> Phase {
        switch e {
        case .napTapped: return .off
        case .wakeTapped: return isOn(p) ? p : .connecting
        case .helperNeedsApproval: return .trouble(.needsApproval)
        case .otherVPNFound: return .trouble(.otherVPN)
        case .sealFailed: return .trouble(.notSealed)
        case .noRoadsFound: return .trouble(.noRoads)
        case .engineFailed: return p == .off ? p : .failed
        default: break
        }
        guard isOn(p) else { return p }
        if p == .hotelLogin {
            // The 5-minute login window ends only by Done, timeout, nap or failure; checks do not end it.
            return e == .hotelLoginEnded ? .connecting : p
        }
        switch e {
        case .hotelLoginStarted: return .hotelLogin
        case .engineReady, .roadsBack: return .connected
        case .roadPicked: return .switching
        case .pickedRoadUnreachable: return .trouble(.roadClosed)
        case .allRoadsDown(let direct): return .trouble(direct ? .allRoadsSleepy : .noInternet)
        default: return p
        }
    }

    public static func mood(_ p: Phase) -> Mood {
        switch p {
        case .off: return .sleeping
        case .connecting, .switching, .hotelLogin, .trouble(.roadClosed): return .sniffing
        case .connected: return .happy
        case .trouble, .failed: return .confused
        }
    }

    public static func status(_ p: Phase, mode: RoadMode = .fast) -> String {
        switch p {
        case .off: return "Napping. Wake me up when you need me"
        case .connecting, .switching: return "Sniffing for a server..."
        case .hotelLogin: return "Log in on the page that opened. I'll close it once you're online"
        case .trouble(.otherVPN): return "Another app is changing your internet. Quit it, then wake me up"
        // Never claim the Mac is blocked when it is not (security review 2026-10-10).
        case .trouble(.notSealed): return "I couldn't block the internet. Turn Wi-Fi off, then open Help"
        case .trouble(.noRoads): return "Add your servers first"
        case .connected:
            switch mode {
            case .secure: return "Connected, cozy and safe"
            case .fast: return "Connected, fast and cozy"
            case .manual: return "Connected on your server"
            }
        case .trouble(.roadClosed): return "This server is blocked here, trying another"
        case .trouble(.allRoadsSleepy): return "All servers are sleepy, I'll keep trying"
        case .trouble(.noInternet): return "No internet at all, check the Wi-Fi"
        case .trouble(.needsApproval): return "I need a one-time OK in System Settings"
        // The kill switch keeps everything blocked until she wakes or naps, so say so plainly.
        case .failed: return "I paused the internet to keep you safe. Press Wake me up to try again"
        }
    }

    /// In China mode napping means no internet at all, so the button says "Go offline".
    public static func buttonTitle(_ p: Phase, chinaMode: Bool = false) -> String {
        if p == .hotelLogin { return "Done" }
        guard isOn(p) else { return "Wake me up" }
        return chinaMode ? "Go offline" : "Let me nap"
    }
}

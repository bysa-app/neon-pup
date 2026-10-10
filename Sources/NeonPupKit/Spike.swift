import Foundation
import NeonPupCore

/// Maintenance commands for the maintainer: `Neon Pup.app/Contents/MacOS/NeonPup --spike <cmd>`.
/// start: register helper, start the engine with the bundled config; stop; status.
@MainActor
public enum Spike {
    public static func run(_ args: [String]) async -> Int32 {
        let helper = HelperClient()
        switch args.first ?? "" {
        case "start":
            switch helper.readiness() {
            case .ready: break
            case .needsApproval:
                print("NEEDS APPROVAL: System Settings > General > Login Items > allow Neon Pup, then rerun")
                helper.openApproval()
                return 2
            case .error(let message):
                print("HELPER ERROR: \(message)")
                return 1
            }
            let access: EngineAccess
            let roads = KeychainRoadStore().load()
            guard !roads.isEmpty else { print("NO SERVERS: add your servers in the app first"); return 1 }
            switch await helper.start(roads: roads) {
            case .failed(let error): print("START ERROR: \(error)"); return 1
            case .started(let granted): access = granted
            }
            UserDefaults.standard.set(access.port, forKey: "engineAPIPort")
            UserDefaults.standard.set(access.secret, forKey: "engineAPISecret")
            print("STARTED api=127.0.0.1:\(access.port)")
            return 0
        case "stop":
            await helper.stop()
            await helper.restoreTimeZone()
            print("STOPPED")
            return 0
        case "reinstall":
            // Unregistering ends the running helper; registering again lets launchd start the new binary.
            print(helper.reinstall())
            return 0
        case "import-roads":
            // Maintenance: same as "Import from file..." + "Save my roads" in the app.
            guard let path = args.dropFirst().first, let text = try? String(contentsOfFile: path, encoding: .utf8) else {
                print("usage: --spike import-roads <file>"); return 64
            }
            var roads: [RoadSpec] = []
            for item in ShareLinkParser.parseAll(text) {
                switch item.result {
                case .success(let road): roads.append(road)
                case .failure(let error): print("REFUSED: \(error.message)"); return 1
                }
            }
            guard KeychainRoadStore().save(roads) else { print("could not save"); return 1 }
            print("imported \(roads.count) roads: " + roads.map(\.name).joined(separator: " | "))
            return 0
        case "killswitch":
            // Drills only. "on" also refreshes the rules for a new tunnel interface.
            if args.dropFirst().first == "report" {
                print(await helper.killSwitchReport())
                return 0
            }
            let on = args.dropFirst().first == "on"
            print("killswitch \(on ? "on" : "off"): \(await helper.setKillSwitch(on) ?? "ok")")
            return 0
        case "tz-apply":
            // Maintenance/drills: same call the app makes on connect. Prints the zone set, or "none".
            print("applied: \(await helper.applyTimeZone() ?? "none")")
            return 0
        case "tz-restore":
            await helper.restoreTimeZone()
            print("restored")
            return 0
        case "status":
            let s = await helper.status()
            print("running=\(s.running) lastError=\(s.lastError ?? "none")")
            return 0
        default:
            print("usage: --spike start|stop|status|reinstall|tz-apply|tz-restore|killswitch on|off")
            return 64
        }
    }
}

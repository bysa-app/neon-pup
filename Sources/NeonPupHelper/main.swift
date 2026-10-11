import Foundation
import NeonPupCore

final class HelperService: NSObject, NeonPupHelperProtocol {
    let engine = EngineSupervisor()
    let timeZone = TimeZoneManager()

    func start(roads: Data, withReply reply: @escaping (Int, String?, String?) -> Void) {
        let (port, secret, error) = engine.start(roads: roads)
        reply(port, secret, error)
    }
    func stop(withReply reply: @escaping () -> Void) { engine.stop(); reply() }
    func status(withReply reply: @escaping (Bool, String?) -> Void) {
        let (running, error) = engine.status()
        reply(running, error)
    }
    func applyTimeZone(withReply reply: @escaping (String?) -> Void) { reply(timeZone.apply()) }
    func restoreTimeZone(withReply reply: @escaping () -> Void) { timeZone.restore(); reply() }
    func killSwitchReport(withReply reply: @escaping (String) -> Void) { reply(engine.killSwitchReport()) }
    func setKillSwitch(_ on: Bool, withReply reply: @escaping (String?) -> Void) { reply(engine.setKillSwitch(on)) }
    func setChinaMode(_ on: Bool, withReply reply: @escaping (String?) -> Void) { reply(engine.setChinaMode(on)) }
    func recentLog(withReply reply: @escaping (String) -> Void) { reply(engine.recentLog()) }
    let hotel = HotelExpiry()
    func installSFM(withReply reply: @escaping (String?) -> Void) { reply(SFMInstaller.install()) }
    func armHotelExpiry(_ seconds: Int, apiPort: Int, secret: String, mode: String, withReply reply: @escaping (Bool) -> Void) {
        reply(hotel.arm(seconds: seconds, apiPort: apiPort, secret: secret, mode: mode))
    }
    func cancelHotelExpiry(withReply reply: @escaping () -> Void) { hotel.cancel(); reply() }
    func version(withReply reply: @escaping (String) -> Void) { reply(HelperConstants.version) }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let service = HelperService()
    private var open = 0
    private let lock = NSLock()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: NeonPupHelperProtocol.self)
        connection.exportedObject = service
        lock.lock(); open += 1; lock.unlock()
        connection.invalidationHandler = { [weak self] in self?.connectionClosed() }
        connection.resume()
        return true
    }

    /// On-demand daemon: with no app connected and the engine off there is nothing to do, so exit and
    /// let launchd start the current binary next time (this is how an app update reaches the helper).
    func exitIfIdle() {
        lock.lock(); let idle = open <= 0; lock.unlock()
        if idle && !service.engine.status().0 && !service.engine.killSwitch.wanted && !service.hotel.pending { exit(0) }
    }

    private func connectionClosed() {
        lock.lock(); open -= 1; let idle = open <= 0; lock.unlock()
        guard idle else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            self.lock.lock(); let stillIdle = self.open <= 0; self.lock.unlock()
            if stillIdle && !self.service.engine.status().0 && !self.service.hotel.pending { exit(0) }
        }
    }
}

let delegate = ListenerDelegate()
// A pending hotel expiry keeps the helper alive; once it settles, exit if nothing else needs it.
delegate.service.hotel.onSettled = { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { delegate.exitIfIdle() } }
// A fresh helper never supervises a running engine: stop any engine a dead helper left behind, and
// restore a leftover time zone record (crash, reboot).
// A block from an earlier boot is dropped unless China mode is on (Codex review 2026-10-10), before stop()
// can seal on it.
delegate.service.engine.applyBootPolicy()
delegate.service.engine.stop()
delegate.service.timeZone.restore()
let listener = NSXPCListener(machServiceName: HelperConstants.machService)
listener.setConnectionCodeSigningRequirement(HelperConstants.clientRequirement)
listener.delegate = delegate
listener.resume()
// Started at boot (RunAtLoad) so China mode is sealed before anything else goes online. When the kill
// switch is not wanted there is nothing to do until the app connects.
if !delegate.service.engine.killSwitch.wanted {
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { delegate.exitIfIdle() }
}
dispatchMain()

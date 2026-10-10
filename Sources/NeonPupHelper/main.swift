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
    func recentLog(withReply reply: @escaping (String) -> Void) { reply(engine.recentLog()) }
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
        if idle && !service.engine.status().0 && !service.engine.killSwitch.wanted { exit(0) }
    }

    private func connectionClosed() {
        lock.lock(); open -= 1; let idle = open <= 0; lock.unlock()
        guard idle else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            self.lock.lock(); let stillIdle = self.open <= 0; self.lock.unlock()
            if stillIdle && !self.service.engine.status().0 { exit(0) }
        }
    }
}

let delegate = ListenerDelegate()
// A fresh helper never supervises a running engine: stop any engine a dead helper left behind, and
// restore a leftover time zone record (crash, reboot).
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

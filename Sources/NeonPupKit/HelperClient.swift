import Foundation
import ServiceManagement
import NeonPupCore

@MainActor
public final class HelperClient: HelperControlling {
    private let service = SMAppService.daemon(plistName: HelperConstants.plistName)
    private var connection: NSXPCConnection?

    public init() {}

    public func readiness() -> HelperReadiness {
        switch service.status {
        case .enabled:
            // An app update leaves the old helper running (launchd keeps it): replace it (final review #8).
            if let running = helperVersion(), running != HelperConstants.version {
                // Replacing the helper stops its engine. Seal first: the pf rules live in the kernel and
                // outlast the old helper, so nothing leaks while the new one is installed (security review).
                sealAndStopOldHelper()
                let result = reinstall()
                return service.status == .enabled && helperVersion() == HelperConstants.version
                    ? .ready : .error("Neon Pup was updated (\(result)). Press Wake me up again")
            }
            return .ready
        case .requiresApproval:
            return .needsApproval
        case .notRegistered, .notFound:
            do { try service.register() } catch {
                return service.status == .requiresApproval ? .needsApproval : .error(error.localizedDescription)
            }
            return service.status == .enabled ? .ready : .needsApproval
        @unknown default:
            return .error("unknown helper status")
        }
    }

    public func openApproval() { SMAppService.openSystemSettingsLoginItems() }

    private func sealAndStopOldHelper() {
        let c = NSXPCConnection(machServiceName: HelperConstants.machService, options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: NeonPupHelperProtocol.self)
        c.resume()
        defer { c.invalidate() }
        guard let old = c.synchronousRemoteObjectProxyWithErrorHandler({ _ in }) as? NeonPupHelperProtocol else { return }
        old.setKillSwitch(true) { _ in }
        old.stop { }
    }

    /// The running helper's version, or nil when it cannot be reached.
    private func helperVersion() -> String? {
        let c = NSXPCConnection(machServiceName: HelperConstants.machService, options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: NeonPupHelperProtocol.self)
        c.resume()
        defer { c.invalidate() }
        var version: String?
        (c.synchronousRemoteObjectProxyWithErrorHandler { _ in } as? NeonPupHelperProtocol)?.version { version = $0 }
        return version
    }

    /// Maintenance: unregister (stops the running helper) and register again.
    public func reinstall() -> String {
        connection?.invalidate()
        connection = nil
        do { try service.unregister() } catch { return "unregister failed: \(error.localizedDescription)" }
        do { try service.register() } catch { return "register failed: \(error.localizedDescription), status \(service.status.rawValue)" }
        return "reinstalled, status \(service.status.rawValue) (1 = enabled, 2 = needs approval)"
    }

    private func call<T>(_ fallback: T, _ body: @escaping (NeonPupHelperProtocol, @escaping (T) -> Void) -> Void) async -> T {
        if connection == nil {
            let c = NSXPCConnection(machServiceName: HelperConstants.machService, options: .privileged)
            c.remoteObjectInterface = NSXPCInterface(with: NeonPupHelperProtocol.self)
            c.invalidationHandler = { [weak self] in Task { @MainActor in self?.connection = nil } }
            c.resume()
            connection = c
        }
        let conn = connection!
        return await withCheckedContinuation { (cont: CheckedContinuation<T, Never>) in
            let once = Once()
            let proxy = conn.remoteObjectProxyWithErrorHandler { _ in once.run { cont.resume(returning: fallback) } }
            guard let helper = proxy as? NeonPupHelperProtocol else { once.run { cont.resume(returning: fallback) }; return }
            body(helper) { value in once.run { cont.resume(returning: value) } }
        }
    }

    public func start(roads: [RoadSpec]) async -> StartResult {
        guard let data = try? JSONEncoder().encode(roads) else { return .failed("the servers could not be saved") }
        return await call(.failed("could not reach the helper")) { h, done in
            h.start(roads: data) { port, secret, error in
                if let error { done(.failed(error)) }
                else if let secret, port > 0 { done(.started(EngineAccess(port: port, secret: secret))) }
                else { done(.failed("the helper gave no engine access")) }
            }
        }
    }
    public func stop() async { await call(()) { h, done in h.stop { done(()) } } }
    public func status() async -> (running: Bool, lastError: String?) {
        await call((false, "could not reach the helper")) { h, done in h.status { done(($0, $1)) } }
    }
    public func applyTimeZone() async -> String? { await call(nil) { h, done in h.applyTimeZone { done($0) } } }
    public func setKillSwitch(_ on: Bool) async -> String? {
        await call("could not reach the helper") { h, done in h.setKillSwitch(on) { done($0) } }
    }

    public func killSwitchReport() async -> String {
        await call("could not reach the helper") { h, done in h.killSwitchReport { done($0) } }
    }

    public func stopNow(keepKillSwitch: Bool) {
        let c = connection ?? {
            let c = NSXPCConnection(machServiceName: HelperConstants.machService, options: .privileged)
            c.remoteObjectInterface = NSXPCInterface(with: NeonPupHelperProtocol.self)
            c.resume()
            connection = c
            return c
        }()
        guard let helper = c.synchronousRemoteObjectProxyWithErrorHandler({ _ in }) as? NeonPupHelperProtocol else { return }
        helper.stop { }
        helper.restoreTimeZone { }
        if !keepKillSwitch { helper.setKillSwitch(false) { _ in } }
    }

    public func restoreTimeZone() async { await call(()) { h, done in h.restoreTimeZone { done(()) } } }
}

/// Guards a continuation against being resumed twice (reply and error handler can both fire).
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func run(_ body: () -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
    }
}

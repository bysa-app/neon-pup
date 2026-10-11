import Foundation
import Network

/// Hands SFM its profile: 127.0.0.1 only, one secret path, anything else 404. SFM imports it as a "remote
/// profile" and fetches it again on its own schedule. The profile holds the server links, so the path is a
/// 32-hex-digit secret kept with the other app settings, and nothing about it goes into reports.
public final class ProfileServer: @unchecked Sendable {
    private let port: UInt16
    private let token: String
    private let lock = NSLock()
    private var body = Data()
    private var listener: NWListener?
    private var sfmFetch: Date?
    /// When SFM itself (not a browser) last fetched the profile.
    public var lastSFMFetch: Date? { lock.lock(); defer { lock.unlock() }; return sfmFetch }

    public init(port: Int, token: String) {
        self.port = UInt16(port)
        self.token = token
    }

    public var url: URL { URL(string: "http://127.0.0.1:\(port)/\(token).json")! }

    public func update(_ profile: Data) {
        lock.lock(); body = profile; lock.unlock()
    }

    /// nil = listening. Starting twice is harmless.
    @discardableResult
    public func start() -> String? {
        lock.lock(); defer { lock.unlock() }
        guard listener == nil else { return nil }
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params)
            l.newConnectionHandler = { [weak self] conn in self?.serve(conn) }
            // A listener that dies (port taken, network reset) is dropped so the next start() opens a new one.
            l.stateUpdateHandler = { [weak self, weak l] state in
                guard let self else { return }
                if case .failed = state {
                    l?.cancel()
                    self.lock.lock(); if self.listener === l { self.listener = nil }; self.lock.unlock()
                }
            }
            l.start(queue: .global(qos: .utility))
            listener = l
            return nil
        } catch {
            return "could not open the local profile address (port \(port))"
        }
    }

    public func stop() { lock.lock(); listener?.cancel(); listener = nil; lock.unlock() }

    private func serve(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .utility))
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self else { conn.cancel(); return }
            let request = String(data: data ?? Data(), encoding: .utf8) ?? ""
            let firstLine = request.split(separator: "\r\n").first ?? ""
            let parts = firstLine.split(separator: " ")
            let path = parts.count > 1 ? String(parts[1].split(separator: "?").first ?? "") : ""
            var response: Data
            if parts.first == "GET", path == "/\(self.token).json" {
                self.lock.lock(); let payload = self.body; self.lock.unlock()
                if request.contains("User-Agent: SFM") { self.lock.lock(); self.sfmFetch = Date(); self.lock.unlock() }
                response = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n".utf8)
                response.append(payload)
            } else {
                response = Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
            }
            conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
        }
    }
}

import Foundation

/// Talks to sing-box's local clash API (127.0.0.1 only, per-launch secret).
public struct EngineAPI: EngineControlling {
    let base: URL
    let secret: String
    let session: URLSession

    public init(port: Int, secret: String, session: URLSession = .shared) {
        self.base = URL(string: "http://127.0.0.1:\(port)")!
        self.secret = secret
        self.session = session
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil, query: [URLQueryItem] = []) -> URLRequest {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!, timeoutInterval: 8)
        req.httpMethod = method
        req.httpBody = body
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return req
    }

    public func delay(of name: String) async -> Int? {
        let req = request("proxies/\(name)/delay", query: [
            URLQueryItem(name: "timeout", value: "5000"),
            URLQueryItem(name: "url", value: "https://www.gstatic.com/generate_204"),
        ])
        guard let (data, response) = try? await session.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let delay = json["delay"] as? Int, delay > 0 else { return nil }
        return delay
    }

    public func knows(_ name: String) async -> Bool? {
        guard let (_, response) = try? await session.data(for: request("proxies/\(name)")),
              let code = (response as? HTTPURLResponse)?.statusCode else { return nil }
        if code == 200 { return true }
        if code == 404 { return false }
        return nil
    }

    public func currentMode() async -> String? {
        guard let (data, response) = try? await session.data(for: request("configs")),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["mode"] as? String
    }

    public func setMode(_ mode: String) async -> Bool {
        let body = try? JSONSerialization.data(withJSONObject: ["mode": mode])
        guard let (_, response) = try? await session.data(for: request("configs", method: "PATCH", body: body)),
              let code = (response as? HTTPURLResponse)?.statusCode else { return false }
        return (200..<300).contains(code)
    }

    public func select(_ name: String, in group: String) async -> Bool {
        let body = try? JSONSerialization.data(withJSONObject: ["name": name])
        guard let (_, response) = try? await session.data(for: request("proxies/\(group)", method: "PUT", body: body)),
              let code = (response as? HTTPURLResponse)?.statusCode else { return false }
        return (200..<300).contains(code)
    }
}

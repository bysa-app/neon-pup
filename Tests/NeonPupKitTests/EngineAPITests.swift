import XCTest
@testable import NeonPupKit

final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var seen: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var req = request
        if let stream = request.httpBodyStream {
            stream.open(); var data = Data(); var buf = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: 1024); if n <= 0 { break }; data.append(buf, count: n) }
            req.httpBody = data
        }
        StubProtocol.seen.append(req)
        let (code, body) = StubProtocol.handler?(request) ?? (500, Data())
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class EngineAPITests: XCTestCase {
    var api: EngineAPI!

    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        api = EngineAPI(port: 23456, secret: "s3cret", session: URLSession(configuration: config))
        StubProtocol.seen = []
    }

    func testDelayParsesAndAuthenticates() async {
        StubProtocol.handler = { _ in (200, Data(#"{"delay":87}"#.utf8)) }
        let delay = await api.delay(of: "sg-reality")
        XCTAssertEqual(delay, 87)
        let req = StubProtocol.seen[0]
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer s3cret")
        XCTAssertEqual(req.url?.host, "127.0.0.1")
        XCTAssertEqual(req.url?.port, 23456)
        XCTAssertTrue(req.url!.path.hasSuffix("/proxies/sg-reality/delay"))
    }

    func testDelayFailureIsNil() async {
        StubProtocol.handler = { _ in (504, Data(#"{"message":"timeout"}"#.utf8)) }
        let delay = await api.delay(of: "us-reality")
        XCTAssertNil(delay)
        StubProtocol.handler = { _ in (200, Data(#"{"delay":0}"#.utf8)) }
        let zero = await api.delay(of: "us-reality")
        XCTAssertNil(zero)
    }

    func testSelectPutsChoice() async throws {
        StubProtocol.handler = { _ in (204, Data()) }
        let ok = await api.select("us-hysteria2", in: "choice")
        XCTAssertTrue(ok)
        let req = StubProtocol.seen[0]
        XCTAssertEqual(req.httpMethod, "PUT")
        XCTAssertTrue(req.url!.path.hasSuffix("/proxies/choice"))
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: String])
        XCTAssertEqual(body["name"], "us-hysteria2")
    }

    func testSelectRefused() async {
        StubProtocol.handler = { _ in (400, Data()) }
        let ok = await api.select("nope", in: "choice")
        XCTAssertFalse(ok)
    }
}

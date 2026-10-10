import XCTest
@testable import NeonPupCore

/// Codex review 2026-10-10, reproduced before fixing.
final class CodexFindingsCoreTests: XCTestCase {
    /// Finding 1: a percent-encoded parameter name must not slip past the pin refusal.
    func testEncodedPinParameterNameIsStillRefused() {
        let link = "hysteria2://probe@example.com:443?insecure=1&%70inSHA256=" + String(repeating: "a", count: 64)
        guard case .failure = ShareLinkParser.parse(link) else { return XCTFail("certificate pin silently dropped") }
    }

    /// Finding 5: IPv6 addresses must be real addresses, not just allowed characters.
    func testMalformedIPv6IsRefused() {
        for host in [":", ":::", "1:2:3", "gggg::1"] {
            var r = RoadValidatorTests.reality; r.host = host
            XCTAssertTrue(RoadValidator.problems(r).contains("address"), host)
        }
        var ok = RoadValidatorTests.reality; ok.host = "2606:4700::1111"
        XCTAssertEqual(RoadValidator.problems(ok), [])
    }

    /// Finding 6: junk in a port range is refused, not rewritten.
    func testMalformedPortRangesAreRefused() {
        for hp in ["443-junk-444", "-443-444", "443-", "443--444", "1-2-3"] {
            guard case .failure = ShareLinkParser.parse("hysteria2://probe@example.com:\(hp)") else {
                return XCTFail("accepted \(hp)")
            }
        }
    }
}

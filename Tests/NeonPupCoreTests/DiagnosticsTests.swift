import XCTest
@testable import NeonPupCore

final class DiagnosticsTests: XCTestCase {
    let specs = [RoadValidatorTests.reality, RoadValidatorTests.hy2, RoadValidatorTests.ws]

    func testSecretsComeFromTheRoads() {
        let secrets = Set(Diagnostics.secrets(from: specs))
        for s in ["11111111-2222-4333-8444-555555555555", "pa55word", "obfs-pass", "/abc123",
                  RoadValidatorTests.reality.publicKey!, "0123456789abcdef", RoadValidatorTests.hy2.publicKeySHA256!] {
            XCTAssertTrue(secrets.contains(s), s)
        }
    }

    func testReportHidesSecretsInsideErrors() {
        let facts = DiagnosticFacts(appVersion: "1.0.0", macOSVersion: "15.1", cpu: "arm64", phase: "failed",
                                    mode: "secure", pickedRoad: nil, roadDelays: ["road-1": 55],
                                    lastError: "FATAL vless 11111111-2222-4333-8444-555555555555 rejected, pa55word", helper: "ready")
        let report = Diagnostics.report(facts, roads: Roads.from(specs), redacting: Diagnostics.secrets(from: specs))
        XCTAssertFalse(report.contains("11111111-2222-4333-8444-555555555555"))
        XCTAssertFalse(report.contains("pa55word"))
        XCTAssertTrue(report.contains("Singapore everyday: 55 ms"))
        XCTAssertTrue(report.contains("Singapore turbo: no answer"))
    }
}

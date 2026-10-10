import XCTest
@testable import NeonPupCore

final class CodeSignatureTests: XCTestCase {
    func testAppleBinaryIsNotOurs() {
        XCTAssertFalse(CodeSignature.isSignedByUs(path: "/bin/ls"))
    }

    func testMissingFileIsNotTrusted() {
        XCTAssertFalse(CodeSignature.isSignedByUs(path: "/nonexistent/sing-box"))
    }

    func testOurSignedEngineIsTrusted() throws {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/Neon Pup.app/Contents/Resources/sing-box").path
        try XCTSkipUnless(FileManager.default.fileExists(atPath: path), "run tools/build.sh first")
        XCTAssertTrue(CodeSignature.isSignedByUs(path: path))
    }
}

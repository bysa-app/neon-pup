import XCTest
@testable import NeonPupCore

/// The root helper only uses an app bundle whose whole signature (code, sing-box, lists, settings)
/// is intact and belongs to Holinic (security review 2026-10-09: no unverified bytes reach root).
final class AppBundleTrustTests: XCTestCase {
    var built: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/Neon Pup.app")
    }

    func testOurBuiltAppIsTrusted() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: built.path), "run tools/build.sh first")
        XCTAssertTrue(AppBundleTrust.isSignedByUs(bundle: built))
    }

    func testEditedSettingsBreakTrust() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: built.path), "run tools/build.sh first")
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("np-trust-\(UUID().uuidString).app")
        try FileManager.default.copyItem(at: built, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        // No settings are bundled any more (own roads); tamper with a China list instead.
        let settings = copy.appendingPathComponent("Contents/Resources/geoip-cn.srs")
        let handle = try FileHandle(forWritingTo: settings)
        handle.seekToEndOfFile(); handle.write(Data(" ".utf8)); try handle.close()
        XCTAssertFalse(AppBundleTrust.isSignedByUs(bundle: copy))
    }

    func testSomeoneElsesAppIsNotTrusted() {
        XCTAssertFalse(AppBundleTrust.isSignedByUs(bundle: URL(fileURLWithPath: "/System/Applications/Calculator.app")))
    }
}

/// Fifth security review (2026-10-09): only Developer ID, never development builds or older versions.
final class AppBundleTrustHardeningTests: XCTestCase {
    var built: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/Neon Pup.app")
    }

    func testDevelopmentSignedCopyIsRejected() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: built.path), "run tools/build.sh first")
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("np-dev-\(UUID().uuidString).app")
        try FileManager.default.copyItem(at: built, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--deep", "--sign", "Apple Development: Tobias Dietz (MJ53CY9N9W)", copy.path]
        sign.standardOutput = FileHandle.nullDevice; sign.standardError = FileHandle.nullDevice
        try sign.run(); sign.waitUntilExit()
        try XCTSkipUnless(sign.terminationStatus == 0, "development identity not available")
        XCTAssertFalse(AppBundleTrust.isSignedByUs(bundle: copy))
    }

    func testVersionFloor() {
        XCTAssertTrue(VersionFloor.allows("2", floor: nil))
        XCTAssertTrue(VersionFloor.allows("2", floor: "2"))
        XCTAssertTrue(VersionFloor.allows("10", floor: "9"))
        XCTAssertFalse(VersionFloor.allows("1", floor: "2"))
        XCTAssertFalse(VersionFloor.allows("9", floor: "10"))
        XCTAssertFalse(VersionFloor.allows("garbage", floor: "1"))
    }

    func testStateFolderMustBeRootOwnedRealFolder() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("np-state-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        XCTAssertFalse(SafeFolder.isRootOwnedRealFolder(tmp.path), "owned by the test user")
        let link = tmp.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/private/var/db")
        XCTAssertFalse(SafeFolder.isRootOwnedRealFolder(link.path), "symlink to a root folder")
        XCTAssertTrue(SafeFolder.isRootOwnedRealFolder("/private/var/db"))
    }
}

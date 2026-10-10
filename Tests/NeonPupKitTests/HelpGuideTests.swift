import XCTest
@testable import NeonPupKit

final class HelpGuideTests: XCTestCase {
    private var doc: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/GUIDE.md")
    }

    /// The printable guide and the in-app guide must say the same thing.
    /// Regenerate with: NEONPUP_WRITE_GUIDE=1 swift test --filter HelpGuideTests
    func testPrintableGuideMatchesTheApp() throws {
        let page = "# Neon Pup\n\n" + HelpGuide.markdown
        if ProcessInfo.processInfo.environment["NEONPUP_WRITE_GUIDE"] == "1" {
            try page.write(to: doc, atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(try String(contentsOf: doc, encoding: .utf8), page, "regenerate docs/GUIDE.md")
    }

    /// Shareable app: plain typing only, and nothing that only makes sense to the people who built it.
    func testGuideIsPlainAndShareable() {
        let all = HelpGuide.allText
        for banned in ["\u{2014}", "\u{2013}", "\u{201C}", "\u{201D}", "\u{2019}", "\u{2026}", "the maintainer", "the user", "road"] {
            XCTAssertFalse(all.contains(banned), banned)
        }
    }

    /// Every message the app can show is explained in the guide.
    func testEveryStatusMessageIsExplained() {
        for line in ["I need a one-time OK in System Settings", "Add your servers first", "Another app is changing your internet",
                     "All servers are sleepy, I'll keep trying", "No internet at all, check the Wi-Fi",
                     "This server is blocked here, trying another", "I couldn't block the internet",
                     "I paused the internet to keep you safe"] {
            XCTAssertTrue(HelpGuide.allText.contains(line), line)
        }
    }
}

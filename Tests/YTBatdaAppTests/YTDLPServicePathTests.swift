import XCTest
@testable import ytBatdaApp

final class YTDLPServicePathTests: XCTestCase {
    func testFallbackSearchOrderPrefersHomebrewBeforeMacPorts() {
        let dirs = YTDLPService.executableSearchDirs(path: "")

        XCTAssertEqual(
            dirs.prefix(4),
            ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin"]
        )
    }

    func testPathEntriesStayAheadOfFallbackDirectories() {
        let dirs = YTDLPService.executableSearchDirs(path: "/custom/bin:/usr/local/bin")

        XCTAssertEqual(dirs.first, "/custom/bin")
        XCTAssertEqual(dirs[1], "/usr/local/bin")
        XCTAssertTrue(dirs.contains("/opt/homebrew/bin"))
        XCTAssertTrue(dirs.contains("/opt/local/bin"))
    }

    func testExecutableSelectionPrefersHomebrewBeforeMacPortsWhenBothExist() {
        let dirs = YTDLPService.executableSearchDirs(path: "")
        let selected = YTDLPService.firstExecutablePath(
            named: "yt-dlp",
            searchDirs: dirs
        ) { candidate in
            candidate == "/opt/homebrew/bin/yt-dlp" || candidate == "/opt/local/bin/yt-dlp"
        }

        XCTAssertEqual(selected, "/opt/homebrew/bin/yt-dlp")
    }

    func testMergedPathIncludesMacPortsAfterHomebrewPaths() {
        let path = YTDLPService.mergedPath(appPath: "/custom/bin")
        XCTAssertTrue(path.hasPrefix("/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:/usr/bin"))
        XCTAssertTrue(path.hasSuffix(":/custom/bin"))
    }
}

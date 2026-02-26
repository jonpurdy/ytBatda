import XCTest
@testable import ytBatdaApp

final class SemanticVersionTests: XCTestCase {
    func testParsesLeadingVTag() throws {
        let version = try SemanticVersion(parsing: "v1.2.3")

        XCTAssertEqual(version.major, 1)
        XCTAssertEqual(version.minor, 2)
        XCTAssertEqual(version.patch, 3)
        XCTAssertEqual(version.description, "1.2.3")
    }

    func testReleaseBeatsPrerelease() throws {
        let prerelease = try SemanticVersion(parsing: "1.2.3-rc.1")
        let release = try SemanticVersion(parsing: "1.2.3")

        XCTAssertLessThan(prerelease, release)
    }

    func testPrereleaseIdentifiersFollowSemverOrdering() throws {
        XCTAssertLessThan(
            try SemanticVersion(parsing: "1.2.3-alpha.1"),
            try SemanticVersion(parsing: "1.2.3-alpha.beta")
        )
        XCTAssertLessThan(
            try SemanticVersion(parsing: "1.2.3-beta"),
            try SemanticVersion(parsing: "1.2.3-beta.2")
        )
        XCTAssertLessThan(
            try SemanticVersion(parsing: "1.2.3-beta.2"),
            try SemanticVersion(parsing: "1.2.3-beta.11")
        )
        XCTAssertLessThan(
            try SemanticVersion(parsing: "1.2.3-rc.1"),
            try SemanticVersion(parsing: "1.2.3")
        )
    }

    func testIgnoresBuildMetadataInComparison() throws {
        XCTAssertEqual(
            try SemanticVersion(parsing: "1.2.3+abc"),
            try SemanticVersion(parsing: "1.2.3+def")
        )
    }
}

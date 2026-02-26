import Foundation
import AppKit

@MainActor
final class AppUpdater: ObservableObject {
    private let releasesClient: GitHubReleasesClient

    init(releasesClient: GitHubReleasesClient = GitHubReleasesClient(owner: "jonpurdy", repo: "ytBatda")) {
        self.releasesClient = releasesClient
    }

    func checkForUpdates(userInitiated: Bool = true) async {
        do {
            let currentVersion = try Self.installedVersion()
            let latestRelease = try await releasesClient.fetchLatestRelease()
            let latestVersion = try SemanticVersion(parsing: latestRelease.tagName)

            if latestVersion > currentVersion {
                presentUpdateAvailable(currentVersion: currentVersion, latestVersion: latestVersion, release: latestRelease)
            } else if userInitiated {
                presentUpToDate(currentVersion: currentVersion)
            }
        } catch {
            if userInitiated {
                presentError(error)
            }
        }
    }

    static func installedVersion(bundle: Bundle = .main) throws -> SemanticVersion {
        let rawVersion =
            (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        guard !rawVersion.isEmpty else {
            throw AppUpdaterError.missingInstalledVersion
        }

        return try SemanticVersion(parsing: rawVersion)
    }

    private func presentUpToDate(currentVersion: SemanticVersion) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "You’re Up to Date"
        alert.informativeText = "Version \(currentVersion) is the newest available version."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentUpdateAvailable(
        currentVersion: SemanticVersion,
        latestVersion: SemanticVersion,
        release: GitHubRelease
    ) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Update Available"
        alert.informativeText = "Version \(latestVersion) is available (you have \(currentVersion))."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.htmlURL)
        }
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Unable to check for updates"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

enum AppUpdaterError: LocalizedError {
    case missingInstalledVersion
    case invalidResponse
    case githubError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .missingInstalledVersion:
            return "The installed app version could not be determined."
        case .invalidResponse:
            return "Received an invalid response from GitHub Releases."
        case let .githubError(statusCode):
            return "GitHub Releases returned HTTP \(statusCode)."
        }
    }
}

struct GitHubRelease: Decodable {
    let tagName: String
    let body: String?
    let htmlURL: URL

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case htmlURL = "html_url"
    }
}

struct GitHubReleasesClient {
    let owner: String
    let repo: String
    var session: URLSession = .shared

    func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ytBatda", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppUpdaterError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AppUpdaterError.githubError(statusCode: http.statusCode)
        }

        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }
}

struct SemanticVersion: Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: [PrereleaseIdentifier]

    var description: String {
        let core = "\(major).\(minor).\(patch)"
        guard !prerelease.isEmpty else { return core }
        return core + "-" + prerelease.map(\.description).joined(separator: ".")
    }

    init(parsing rawValue: String) throws {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let noPrefix = trimmed.hasPrefix("v") || trimmed.hasPrefix("V") ? String(trimmed.dropFirst()) : trimmed
        let withoutBuild = noPrefix.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        let versionAndPrerelease = withoutBuild[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)

        let coreParts = versionAndPrerelease[0].split(separator: ".", omittingEmptySubsequences: false)
        guard coreParts.count == 3,
              let major = Int(coreParts[0]),
              let minor = Int(coreParts[1]),
              let patch = Int(coreParts[2]) else {
            throw SemanticVersionError.invalidFormat(rawValue)
        }

        self.major = major
        self.minor = minor
        self.patch = patch

        if versionAndPrerelease.count == 2 {
            let identifiers = versionAndPrerelease[1].split(separator: ".", omittingEmptySubsequences: false)
            guard !identifiers.isEmpty else {
                throw SemanticVersionError.invalidFormat(rawValue)
            }
            self.prerelease = try identifiers.map { try PrereleaseIdentifier(parsing: String($0), source: rawValue) }
        } else {
            self.prerelease = []
        }
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        if lhs.prerelease.isEmpty && rhs.prerelease.isEmpty { return false }
        if lhs.prerelease.isEmpty { return false } // Release > prerelease.
        if rhs.prerelease.isEmpty { return true }

        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            return left < right
        }

        return lhs.prerelease.count < rhs.prerelease.count
    }
}

enum SemanticVersionError: LocalizedError {
    case invalidFormat(String)

    var errorDescription: String? {
        switch self {
        case let .invalidFormat(value):
            return "Invalid semantic version: \(value)"
        }
    }
}

enum PrereleaseIdentifier: Comparable, CustomStringConvertible {
    case numeric(Int)
    case string(String)

    var description: String {
        switch self {
        case let .numeric(value):
            return String(value)
        case let .string(value):
            return value
        }
    }

    init(parsing rawValue: String, source: String) throws {
        guard !rawValue.isEmpty else {
            throw SemanticVersionError.invalidFormat(source)
        }

        if let numeric = Int(rawValue) {
            self = .numeric(numeric)
        } else {
            self = .string(rawValue)
        }
    }

    static func < (lhs: PrereleaseIdentifier, rhs: PrereleaseIdentifier) -> Bool {
        switch (lhs, rhs) {
        case let (.numeric(left), .numeric(right)):
            return left < right
        case let (.string(left), .string(right)):
            return left < right
        case (.numeric, .string):
            return true
        case (.string, .numeric):
            return false
        }
    }
}

import Foundation

enum DownloadState: Equatable {
    case idle
    case fetchingFormats
    case preparingDownload
    case runningDownload
    case cancelled
    case success(String)
    case failure(String)

    var label: String {
        switch self {
        case .idle:
            return "Ready"
        case .fetchingFormats:
            return "Getting formats..."
        case .preparingDownload:
            return "Preparing download..."
        case .runningDownload:
            return "Downloading..."
        case .cancelled:
            return "Cancelled"
        case .success(let msg):
            return "Success: \(msg)"
        case .failure(let msg):
            return "Error: \(msg)"
        }
    }
}

struct DownloadRequest {
    let url: String
    let outputDirectory: URL
    let ytDLPExecutable: URL?
    let formatExpression: String?
    let subtitles: SubtitleOptions
}

struct SubtitleOptions: Sendable {
    let enabled: Bool
    let language: String
    let embed: Bool
}

struct FormatDiscoveryResult: Sendable {
    let formats: [YTDLPFormat]
    let subtitleLanguages: [String]
}

struct YTDLPFormat: Identifiable, Hashable, Sendable {
    let id: String
    let ext: String
    let note: String
    let hasVideo: Bool
    let hasAudio: Bool

    var displayName: String {
        let type: String
        if hasVideo && hasAudio {
            type = "Video+Audio"
        } else if hasVideo {
            type = "Video"
        } else {
            type = "Audio"
        }
        return "\(id) - \(ext.uppercased()) - \(note) [\(type)]"
    }
}

enum DownloadError: LocalizedError {
    case invalidURL
    case missingOutputDirectory
    case missingBinary
    case noFormatsAvailable
    case invalidFormatData
    case cancelled
    case processFailed(code: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid http(s) URL."
        case .missingOutputDirectory:
            return "Choose an output folder."
        case .missingBinary:
            return "yt-dlp was not found. Install it or select its binary path."
        case .noFormatsAvailable:
            return "No downloadable formats were found for this URL."
        case .invalidFormatData:
            return "Could not parse formats from yt-dlp output."
        case .cancelled:
            return "Download cancelled."
        case .processFailed(let code, let output):
            return "yt-dlp failed (exit \(code)).\n\(output)"
        }
    }
}

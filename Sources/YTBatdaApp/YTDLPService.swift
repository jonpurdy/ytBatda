import Foundation

protocol DownloadServicing {
    @MainActor
    func fetchFormats(
        for url: String,
        ytDLPExecutable: URL?,
        debugSink: @escaping @Sendable @MainActor (String) -> Void
    ) async throws -> FormatDiscoveryResult

    @MainActor
    func download(
        _ request: DownloadRequest,
        debugSink: @escaping @Sendable @MainActor (String) -> Void,
        progressSink: @escaping @Sendable @MainActor (Double) -> Void,
        phaseSink: @escaping @Sendable @MainActor (String) -> Void
    ) async throws -> String

    func cancelActiveDownload()

    func resolvedExecutablePath(explicit: URL?) -> String?
}

struct YTDLPService: DownloadServicing, Sendable {
    private static let activeDownload = ActiveDownloadManager()
    static let fallbackExecutableSearchDirs = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/opt/local/bin",
        "/usr/bin"
    ]

    func cancelActiveDownload() {
        Self.activeDownload.cancelActiveDownload()
    }

    func resolvedExecutablePath(explicit: URL?) -> String? {
        (try? resolveExecutable(explicit: explicit).path)
    }

    @MainActor
    func fetchFormats(
        for url: String,
        ytDLPExecutable: URL?,
        debugSink: @escaping @Sendable @MainActor (String) -> Void
    ) async throws -> FormatDiscoveryResult {
        let normalizedURL = try validateURL(url)
        let executable = try resolveExecutable(explicit: ytDLPExecutable)

        let args = [
            "-J",
            "--no-playlist",
            normalizedURL
        ]

        let result = try await runProcess(executable: executable.path, arguments: args)
        debugSink(formatDebugBlock(title: "Get Formats", result: result))

        guard result.exitCode == 0 else {
            throw DownloadError.processFailed(code: result.exitCode, output: mergedOutput(result))
        }

        return try parseDiscovery(jsonOutput: result.stdout, fallbackText: mergedOutput(result))
    }

    @MainActor
    func download(
        _ request: DownloadRequest,
        debugSink: @escaping @Sendable @MainActor (String) -> Void,
        progressSink: @escaping @Sendable @MainActor (Double) -> Void,
        phaseSink: @escaping @Sendable @MainActor (String) -> Void
    ) async throws -> String {
        let normalizedURL = try validateURL(request.url)
        let executable = try resolveExecutable(explicit: request.ytDLPExecutable)

        let outputTemplate = request.outputDirectory
            .appendingPathComponent("%(title)s.%(ext)s")
            .path

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytdlmac", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        var args: [String]
        if let formatExpression = request.formatExpression, !formatExpression.isEmpty {
            args = [
                "--newline",
                "--no-playlist",
                "--paths", "temp:\(tempDir.path)",
                "-f", formatExpression,
                "-o", outputTemplate,
                normalizedURL
            ]
        } else {
            args = [
                "--newline",
                "--no-playlist",
                "--paths", "temp:\(tempDir.path)",
                "-o", outputTemplate,
                normalizedURL
            ]
        }

        if request.subtitles.enabled {
            args += [
                "--write-subs",
                "--write-auto-subs",
                "--sub-langs", request.subtitles.language,
                "--sub-format", "best/srt"
            ]
            if request.subtitles.embed {
                args += ["--embed-subs", "--compat-options", "no-keep-subs"]
            } else {
                args.append("--keep-subs")
            }
        }

        let result = try await runProcessStreamingDownload(
            executable: executable.path,
            arguments: args,
            tempDir: tempDir,
            progressSink: progressSink,
            phaseSink: phaseSink
        )
        debugSink(formatDebugBlock(title: "Download", result: result))

        if result.wasCancelled {
            throw DownloadError.cancelled
        }

        if result.exitCode == 0 {
            return request.outputDirectory.path
        }

        throw DownloadError.processFailed(code: result.exitCode, output: mergedOutput(result))
    }

    private func validateURL(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed), ["http", "https"].contains(parsed.scheme?.lowercased()) else {
            throw DownloadError.invalidURL
        }
        return trimmed
    }

    private func parseDiscovery(jsonOutput: String, fallbackText: String) throws -> FormatDiscoveryResult {
        let jsonText = extractJSONObject(from: jsonOutput) ?? extractJSONObject(from: fallbackText) ?? jsonOutput

        guard let data = jsonText.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let formatsArray = object["formats"] as? [[String: Any]] else {
            throw DownloadError.invalidFormatData
        }

        var seen = Set<String>()
        var parsed: [YTDLPFormat] = []

        for item in formatsArray {
            guard let id = item["format_id"] as? String, !id.isEmpty else { continue }
            guard !seen.contains(id) else { continue }

            let vcodec = (item["vcodec"] as? String) ?? "none"
            let acodec = (item["acodec"] as? String) ?? "none"
            let hasVideo = vcodec != "none"
            let hasAudio = acodec != "none"
            guard hasVideo || hasAudio else { continue }

            let ext = (item["ext"] as? String) ?? "unknown"
            let note = makeNote(from: item)

            parsed.append(YTDLPFormat(id: id, ext: ext, note: note, hasVideo: hasVideo, hasAudio: hasAudio))
            seen.insert(id)
        }

        guard !parsed.isEmpty else {
            throw DownloadError.noFormatsAvailable
        }

        let subtitleLanguages = extractSubtitleLanguages(from: object)
        return FormatDiscoveryResult(formats: parsed, subtitleLanguages: subtitleLanguages)
    }

    private func extractSubtitleLanguages(from object: [String: Any]) -> [String] {
        var langs = Set<String>()

        if let subtitles = object["subtitles"] as? [String: Any] {
            langs.formUnion(subtitles.keys.filter { !$0.isEmpty })
        }
        if let automatic = object["automatic_captions"] as? [String: Any] {
            langs.formUnion(automatic.keys.filter { !$0.isEmpty })
        }

        return langs.sorted()
    }

    private func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start <= end else {
            return nil
        }
        return String(text[start...end])
    }

    private func makeNote(from item: [String: Any]) -> String {
        if let format = item["format"] as? String, !format.isEmpty {
            return format
        }

        var parts: [String] = []

        if let resolution = item["resolution"] as? String, !resolution.isEmpty, resolution != "audio only" {
            parts.append(resolution)
        } else if let height = item["height"] as? Int {
            parts.append("\(height)p")
        }

        if let fps = item["fps"] as? Int {
            parts.append("\(fps)fps")
        }

        if let abr = item["abr"] as? Double {
            parts.append("\(Int(abr))k")
        } else if let tbr = item["tbr"] as? Double {
            parts.append("\(Int(tbr))k")
        }

        if let formatNote = item["format_note"] as? String, !formatNote.isEmpty {
            parts.append(formatNote)
        }

        return parts.isEmpty ? "unknown" : parts.joined(separator: ", ")
    }

    private func resolveExecutable(explicit: URL?) throws -> URL {
        if let explicit {
            guard FileManager.default.isExecutableFile(atPath: explicit.path) else {
                throw DownloadError.missingBinary
            }
            return explicit
        }

        let searchDirs = Self.executableSearchDirs(path: ProcessInfo.processInfo.environment["PATH"] ?? "")
        if let path = Self.firstExecutablePath(
            named: "yt-dlp",
            searchDirs: searchDirs,
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) }
        ) {
            return URL(fileURLWithPath: path)
        }

        throw DownloadError.missingBinary
    }

    private func mergedOutput(_ result: ProcessResult) -> String {
        [result.stderr, result.stdout]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func formatDebugBlock(title: String, result: ProcessResult) -> String {
        """
        === \(title) ===
        Command: \(result.command)
        PATH: \(result.path)
        Exit: \(result.exitCode)
        Cancelled: \(result.wasCancelled)
        --- STDERR ---
        \(result.stderr.isEmpty ? "(empty)" : result.stderr)
        --- STDOUT ---
        \(result.stdout.isEmpty ? "(empty)" : result.stdout)

        """
    }

    private func runProcess(executable: String, arguments: [String]) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let stdoutURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("stdout")
                let stderrURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("stderr")

                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: executable)
                    process.arguments = arguments
                    process.environment = mergedEnvironment()

                    FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
                    FileManager.default.createFile(atPath: stderrURL.path, contents: nil)

                    let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
                    let stderrHandle = try FileHandle(forWritingTo: stderrURL)
                    process.standardOutput = stdoutHandle
                    process.standardError = stderrHandle

                    try process.run()
                    process.waitUntilExit()

                    try stdoutHandle.close()
                    try stderrHandle.close()

                    let stdoutData = (try? Data(contentsOf: stdoutURL)) ?? Data()
                    let stderrData = (try? Data(contentsOf: stderrURL)) ?? Data()

                    let result = ProcessResult(
                        exitCode: process.terminationStatus,
                        stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                        stderr: String(data: stderrData, encoding: .utf8) ?? "",
                        command: shellCommand(executable: executable, arguments: arguments),
                        path: process.environment?["PATH"] ?? "",
                        wasCancelled: false
                    )

                    try? FileManager.default.removeItem(at: stdoutURL)
                    try? FileManager.default.removeItem(at: stderrURL)
                    continuation.resume(returning: result)
                } catch {
                    try? FileManager.default.removeItem(at: stdoutURL)
                    try? FileManager.default.removeItem(at: stderrURL)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runProcessStreamingDownload(
        executable: String,
        arguments: [String],
        tempDir: URL,
        progressSink: @escaping @Sendable @MainActor (Double) -> Void,
        phaseSink: @escaping @Sendable @MainActor (String) -> Void
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: executable)
                    process.arguments = arguments
                    process.environment = mergedEnvironment()

                    let stdoutPipe = Pipe()
                    let stderrPipe = Pipe()
                    process.standardOutput = stdoutPipe
                    process.standardError = stderrPipe

                    let collector = LiveOutputCollector()
                    let stdoutReader = stdoutPipe.fileHandleForReading
                    let stderrReader = stderrPipe.fileHandleForReading

                    stdoutReader.readabilityHandler = { handle in
                        let data = handle.availableData
                        collector.append(data, to: .stdout, progressSink: progressSink, phaseSink: phaseSink)
                    }
                    stderrReader.readabilityHandler = { handle in
                        let data = handle.availableData
                        collector.append(data, to: .stderr, progressSink: progressSink, phaseSink: phaseSink)
                    }

                    Self.activeDownload.register(process: process, tempDir: tempDir)
                    try process.run()
                    process.waitUntilExit()

                    stdoutReader.readabilityHandler = nil
                    stderrReader.readabilityHandler = nil

                    collector.append(stdoutReader.readDataToEndOfFile(), to: .stdout, progressSink: progressSink, phaseSink: phaseSink)
                    collector.append(stderrReader.readDataToEndOfFile(), to: .stderr, progressSink: progressSink, phaseSink: phaseSink)
                    collector.finish(progressSink: progressSink, phaseSink: phaseSink)

                    let wasCancelled = Self.activeDownload.finish(process: process)

                    let result = ProcessResult(
                        exitCode: process.terminationStatus,
                        stdout: collector.stdout,
                        stderr: collector.stderr,
                        command: shellCommand(executable: executable, arguments: arguments),
                        path: process.environment?["PATH"] ?? "",
                        wasCancelled: wasCancelled
                    )

                    continuation.resume(returning: result)
                } catch {
                    _ = Self.activeDownload.finish(process: nil)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func shellCommand(executable: String, arguments: [String]) -> String {
        ([executable] + arguments).map(quoteShell).joined(separator: " ")
    }

    private func quoteShell(_ value: String) -> String {
        if value.range(of: #"[^A-Za-z0-9_./:-]"#, options: .regularExpression) == nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func mergedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Self.mergedPath(appPath: env["PATH"] ?? "")
        return env
    }
}

extension YTDLPService {
    static func executableSearchDirs(path: String) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()

        for dir in path.split(separator: ":").map(String.init) + fallbackExecutableSearchDirs {
            guard !dir.isEmpty else { continue }
            if seen.insert(dir).inserted {
                ordered.append(dir)
            }
        }

        return ordered
    }

    static func firstExecutablePath(
        named executableName: String,
        searchDirs: [String],
        isExecutable: (String) -> Bool
    ) -> String? {
        for dir in searchDirs {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent(executableName).path
            if isExecutable(candidate) {
                return candidate
            }
        }
        return nil
    }

    static func mergedPath(appPath: String) -> String {
        let preferred = fallbackExecutableSearchDirs + ["/bin", "/usr/sbin", "/sbin"]
        let preferredPath = preferred.joined(separator: ":")
        if appPath.isEmpty {
            return preferredPath
        }
        return preferredPath + ":" + appPath
    }
}

private struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let command: String
    let path: String
    let wasCancelled: Bool
}

private enum OutputStream {
    case stdout
    case stderr
}

private final class LiveOutputCollector: @unchecked Sendable {
    private let lock = NSLock()

    private var stdoutBuffer = ""
    private var stderrBuffer = ""
    private var stdoutRemainder = ""
    private var stderrRemainder = ""
    private var currentProgress: Double = 0
    private var currentPhase: String = "video"

    var stdout: String {
        lock.lock()
        defer { lock.unlock() }
        return stdoutBuffer
    }

    var stderr: String {
        lock.lock()
        defer { lock.unlock() }
        return stderrBuffer
    }

    func append(
        _ data: Data,
        to stream: OutputStream,
        progressSink: @escaping @Sendable @MainActor (Double) -> Void,
        phaseSink: @escaping @Sendable @MainActor (String) -> Void
    ) {
        guard !data.isEmpty else { return }

        let chunk = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r", with: "\n")

        let lines: [String]
        lock.lock()
        switch stream {
        case .stdout:
            stdoutBuffer += chunk
            stdoutRemainder += chunk
            let parts = stdoutRemainder.components(separatedBy: "\n")
            stdoutRemainder = parts.last ?? ""
            lines = Array(parts.dropLast())
        case .stderr:
            stderrBuffer += chunk
            stderrRemainder += chunk
            let parts = stderrRemainder.components(separatedBy: "\n")
            stderrRemainder = parts.last ?? ""
            lines = Array(parts.dropLast())
        }
        lock.unlock()

        emitProgress(from: lines, progressSink: progressSink, phaseSink: phaseSink)
    }

    func finish(
        progressSink: @escaping @Sendable @MainActor (Double) -> Void,
        phaseSink: @escaping @Sendable @MainActor (String) -> Void
    ) {
        let tailLines: [String]
        lock.lock()
        tailLines = [stdoutRemainder, stderrRemainder].filter { !$0.isEmpty }
        stdoutRemainder = ""
        stderrRemainder = ""
        lock.unlock()

        emitProgress(from: tailLines, progressSink: progressSink, phaseSink: phaseSink)
    }

    private func emitProgress(
        from lines: [String],
        progressSink: @escaping @Sendable @MainActor (Double) -> Void,
        phaseSink: @escaping @Sendable @MainActor (String) -> Void
    ) {
        for line in lines {
            if let nextPhase = Self.extractPhase(from: line) {
                let shouldEmit: Bool
                lock.lock()
                shouldEmit = nextPhase != currentPhase
                if shouldEmit {
                    currentPhase = nextPhase
                }
                lock.unlock()
                if shouldEmit {
                    Task { @MainActor in
                        phaseSink(nextPhase)
                    }
                }
            }

            let update: Double?
            lock.lock()
            if Self.isDownloadStartLine(line) {
                currentProgress = 0
                update = 0
            } else if let candidate = Self.extractProgress(from: line) {
                currentProgress = candidate
                update = candidate
            } else {
                update = nil
            }
            lock.unlock()

            if let value = update {
                Task { @MainActor in
                    progressSink(value)
                }
            }
        }
    }

    private static func extractProgress(from line: String) -> Double? {
        guard line.contains("[download]") || line.contains("download:") else {
            return nil
        }

        guard let range = line.range(of: #"(\d+(?:\.\d+)?)%"#, options: .regularExpression) else {
            return nil
        }

        let numberText = line[range].replacing("%", with: "")
        guard let value = Double(numberText) else {
            return nil
        }

        return min(max(value / 100.0, 0), 1)
    }

    private static func isDownloadStartLine(_ line: String) -> Bool {
        line.contains("[download] Destination:") || line.contains("[download] Downloading item")
    }

    private static func extractPhase(from line: String) -> String? {
        let lower = line.lowercased()
        if lower.contains("subtitle") || lower.contains(".vtt") || lower.contains(".srt") || lower.contains(".ass") || lower.contains(".lrc") {
            return "subtitles"
        }
        if lower.contains("audio only")
            || lower.contains(".m4a")
            || lower.contains(".mka")
            || lower.contains(".mp3")
            || lower.contains(".aac")
            || lower.contains(".opus")
            || lower.contains(".flac") {
            return "audio"
        }
        if lower.contains("video only")
            || lower.contains(".mp4")
            || lower.contains(".webm")
            || lower.contains(".mkv")
            || lower.contains(".mov")
            || lower.contains(".avi") {
            return "video"
        }
        if lower.contains("merging formats") || lower.contains("[merger]") || lower.contains("post-process") {
            return "processing"
        }
        return nil
    }
}

private final class ActiveDownloadManager: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var tempDir: URL?
    private var didCancel = false

    func register(process: Process, tempDir: URL) {
        lock.lock()
        self.process = process
        self.tempDir = tempDir
        didCancel = false
        lock.unlock()
    }

    func cancelActiveDownload() {
        var proc: Process?
        var dir: URL?

        lock.lock()
        didCancel = true
        proc = process
        dir = tempDir
        lock.unlock()

        proc?.terminate()

        if let dir {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    func finish(process finishedProcess: Process?) -> Bool {
        var dir: URL?
        var wasCancelled = false

        lock.lock()
        let sameProcess = finishedProcess == nil || process === finishedProcess
        if sameProcess {
            dir = tempDir
            tempDir = nil
            process = nil
            wasCancelled = didCancel
            didCancel = false
        }
        lock.unlock()

        if let dir {
            try? FileManager.default.removeItem(at: dir)
        }

        return wasCancelled
    }
}

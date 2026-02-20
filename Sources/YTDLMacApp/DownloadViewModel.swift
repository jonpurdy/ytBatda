import Foundation

@MainActor
final class DownloadViewModel: ObservableObject {
    @Published var videoURL: String = ""
    @Published var outputDirectory: URL?
    @Published var ytDLPBinary: URL?
    @Published var state: DownloadState = .idle
    @Published var processOutput: String = ""
    @Published var debugOutput: String = ""
    @Published var isRunning: Bool = false
    @Published var downloadProgress: Double? = nil
    @Published var currentDownloadPhase: String = "video"

    @Published var combinedFormats: [YTDLPFormat] = []
    @Published var videoOnlyFormats: [YTDLPFormat] = []
    @Published var audioOnlyFormats: [YTDLPFormat] = []

    @Published var selectedVideoFormatID: String?
    @Published var selectedAudioFormatID: String?
    @Published var subtitlesEnabled: Bool = false {
        didSet {
            if subtitlesEnabled {
                subtitlesEmbed = true
            }
        }
    }
    @Published var subtitlesEmbed: Bool = false
    @Published var availableSubtitleLanguages: [String] = []
    @Published var selectedSubtitleLanguage: String = "en"
    @Published var ytDLPDetectedPath: String?

    private let service: any DownloadServicing
    private var formatsURL: String?
    private let skipSelectionID = "__skip__"

    init(service: DownloadServicing) {
        self.service = service
        outputDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
        refreshBinaryStatus()
    }

    var ytDLPAvailable: Bool {
        ytDLPDetectedPath != nil
    }

    var ytDLPStatusMessage: String {
        if let path = ytDLPDetectedPath {
            return "yt-dlp detected at \(path)"
        }
        return "yt-dlp not found. Install it or choose a binary path."
    }

    var hasCurrentFormats: Bool {
        formatsURL == normalizedURL && (!combinedFormats.isEmpty || !videoOnlyFormats.isEmpty || !audioOnlyFormats.isEmpty)
    }

    var isFetchingFormats: Bool {
        state == .fetchingFormats && isRunning
    }

    var isDownloading: Bool {
        (state == .preparingDownload || state == .runningDownload) && isRunning
    }

    var canGetFormats: Bool {
        ytDLPAvailable && !isRunning && !hasCurrentFormats
    }

    var canTapDownload: Bool {
        isDownloading || (ytDLPAvailable && hasCurrentFormats && !isRunning)
    }

    var subtitlesConfirmedAvailable: Bool {
        hasCurrentFormats && !availableSubtitleLanguages.isEmpty
    }

    var formatBreakdownText: String {
        let total = combinedFormats.count + videoOnlyFormats.count + audioOnlyFormats.count
        return "Loaded \(total): \(combinedFormats.count) combined, \(videoOnlyFormats.count) video-only, \(audioOnlyFormats.count) audio-only."
    }

    var downloadPhaseLabel: String {
        "Downloading \(currentDownloadPhase.capitalized)..."
    }

    func invalidateFormatsIfNeeded() {
        if formatsURL != nil, formatsURL != normalizedURL {
            clearFormats()
        }
    }

    func refreshBinaryStatus() {
        ytDLPDetectedPath = service.resolvedExecutablePath(explicit: ytDLPBinary)
    }

    func getFormats() {
        guard !isRunning else { return }
        refreshBinaryStatus()
        guard ytDLPAvailable else {
            state = .failure(DownloadError.missingBinary.localizedDescription)
            return
        }

        state = .fetchingFormats
        processOutput = "Fetching available formats..."
        downloadProgress = nil
        isRunning = true

        Task {
            defer { isRunning = false }

            do {
                let discovery = try await service.fetchFormats(
                    for: normalizedURL,
                    ytDLPExecutable: ytDLPBinary,
                    debugSink: { [weak self] block in
                        self?.appendDebug(block)
                    }
                )
                applyFormats(discovery.formats)
                applySubtitleLanguages(discovery.subtitleLanguages)
                formatsURL = normalizedURL
                state = .success("Formats loaded. Choose format(s), then download.")
                processOutput = formatBreakdownText
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                state = .failure(message)
                processOutput = message
                clearFormats()
            }
        }
    }

    func runDownload() {
        guard !isRunning else { return }
        refreshBinaryStatus()
        guard ytDLPAvailable else {
            state = .failure(DownloadError.missingBinary.localizedDescription)
            return
        }

        guard hasCurrentFormats else {
            state = .failure("Get formats first.")
            return
        }

        guard let outputDirectory else {
            state = .failure(DownloadError.missingOutputDirectory.localizedDescription)
            return
        }

        state = .preparingDownload
        processOutput = hasCurrentFormats ? "" : "Using yt-dlp default format selection."
        downloadProgress = 0
        currentDownloadPhase = initialDownloadPhase
        isRunning = true

        Task {
            defer { isRunning = false }

            do {
                state = .runningDownload
                let request = DownloadRequest(
                    url: normalizedURL,
                    outputDirectory: outputDirectory,
                    ytDLPExecutable: ytDLPBinary,
                    formatExpression: selectedFormatExpression,
                    subtitles: subtitleOptions
                )
                let savedPath = try await service.download(
                    request,
                    debugSink: { [weak self] block in
                        self?.appendDebug(block)
                    },
                    progressSink: { [weak self] progress in
                        self?.downloadProgress = progress
                    },
                    phaseSink: { [weak self] phase in
                        self?.currentDownloadPhase = phase
                    }
                )
                downloadProgress = 1
                state = .success("Saved to \(savedPath)")
            } catch {
                if case DownloadError.cancelled = error {
                    state = .cancelled
                    processOutput = "Download cancelled."
                    downloadProgress = nil
                    return
                }
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                state = .failure(message)
                processOutput = message
                downloadProgress = nil
            }
        }
    }

    func cancelDownload() {
        guard isDownloading else { return }
        service.cancelActiveDownload()
    }

    func clearDebugOutput() {
        debugOutput = ""
    }

    private func appendDebug(_ block: String) {
        if debugOutput.isEmpty {
            debugOutput = block
        } else {
            debugOutput += "\n" + block
        }
    }

    private var selectedFormatExpression: String? {
        guard hasCurrentFormats else { return nil }

        let video = normalizedSelection(selectedVideoFormatID)
        let audio = normalizedSelection(selectedAudioFormatID)

        if let video, let audio {
            return video == audio ? video : "\(video)+\(audio)"
        }
        if let video {
            return video
        }
        if let audio {
            return audio
        }
        return nil
    }

    private var normalizedURL: String {
        videoURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var subtitleOptions: SubtitleOptions {
        SubtitleOptions(
            enabled: subtitlesEnabled,
            language: selectedSubtitleLanguage,
            embed: subtitlesEmbed
        )
    }

    private var initialDownloadPhase: String {
        let video = normalizedSelection(selectedVideoFormatID)
        let audio = normalizedSelection(selectedAudioFormatID)
        if video == nil, audio != nil {
            return "audio"
        }
        return "video"
    }

    private func applyFormats(_ formats: [YTDLPFormat]) {
        combinedFormats = formats.filter { $0.hasVideo && $0.hasAudio }
        videoOnlyFormats = formats.filter { $0.hasVideo && !$0.hasAudio }
        audioOnlyFormats = formats.filter { !$0.hasVideo && $0.hasAudio }

        selectedVideoFormatID = defaultVideoSelectionID
        selectedAudioFormatID = defaultAudioSelectionID
    }

    var videoPickerFormats: [YTDLPFormat] {
        if !videoOnlyFormats.isEmpty {
            return videoOnlyFormats
        }
        return combinedFormats
    }

    var audioPickerFormats: [YTDLPFormat] {
        if !audioOnlyFormats.isEmpty {
            return audioOnlyFormats
        }
        return combinedFormats
    }

    var defaultVideoSelectionID: String? {
        guard !videoPickerFormats.isEmpty else { return nil }
        return videoOnlyFormats.isEmpty ? "best" : "bestvideo"
    }

    var defaultAudioSelectionID: String? {
        guard !audioPickerFormats.isEmpty else { return nil }
        return audioOnlyFormats.isEmpty ? "best" : "bestaudio"
    }

    var defaultVideoSelectionLabel: String {
        defaultVideoSelectionID == "bestvideo" ? "Best Video (yt-dlp)" : "Best Format (yt-dlp)"
    }

    var defaultAudioSelectionLabel: String {
        defaultAudioSelectionID == "bestaudio" ? "Best Audio (yt-dlp)" : "Best Format (yt-dlp)"
    }

    var skipVideoSelectionID: String {
        skipSelectionID
    }

    var skipAudioSelectionID: String {
        skipSelectionID
    }

    var hasExplicitFormatSelection: Bool {
        selectedVideoFormatID != nil || selectedAudioFormatID != nil
    }

    var selectedFormatSummary: String {
        let video = normalizedSelection(selectedVideoFormatID)
        let audio = normalizedSelection(selectedAudioFormatID)

        switch (video, audio) {
        case let (video?, audio?):
            return video == audio ? "Selected format: \(video)" : "Selected combination: \(video)+\(audio)"
        case let (video?, nil):
            return "Selected video-only format: \(video)"
        case let (nil, audio?):
            return "Selected audio-only format: \(audio)"
        case (nil, nil):
            return "Both video and audio are skipped. Download will use yt-dlp defaults."
        }
    }

    private func normalizedSelection(_ value: String?) -> String? {
        guard let value else { return nil }
        return value == skipSelectionID ? nil : value
    }

    private func clearSelections() {
        selectedVideoFormatID = nil
        selectedAudioFormatID = nil
    }

    private func clearFormats() {
        formatsURL = nil
        combinedFormats = []
        videoOnlyFormats = []
        audioOnlyFormats = []
        availableSubtitleLanguages = []
        subtitlesEnabled = false
        subtitlesEmbed = false
        clearSelections()
    }

    private func applySubtitleLanguages(_ languages: [String]) {
        availableSubtitleLanguages = languages
        if languages.isEmpty {
            subtitlesEnabled = false
            subtitlesEmbed = false
        }
        if selectedSubtitleLanguage.isEmpty {
            selectedSubtitleLanguage = "en"
        } else if !languages.isEmpty && !languages.contains(selectedSubtitleLanguage) {
            selectedSubtitleLanguage = languages[0]
        }
    }
}

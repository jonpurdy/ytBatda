import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var viewModel: DownloadViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Video URL")
                    .font(.headline)
                TextField("https://...", text: $viewModel.videoURL)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: viewModel.videoURL) { _, _ in
                        viewModel.invalidateFormatsIfNeeded()
                    }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Output Folder")
                        .font(.headline)
                    Spacer()
                    Button("Choose") {
                        viewModel.outputDirectory = pickDirectory()
                    }
                }
                Text(viewModel.outputDirectory?.path ?? "Not selected")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("yt-dlp Binary (Optional)")
                        .font(.headline)
                    Spacer()
                    Button("Choose") {
                        viewModel.ytDLPBinary = pickExecutable()
                        viewModel.refreshBinaryStatus()
                    }
                }
                Text(viewModel.ytDLPBinary?.path ?? "Using yt-dlp from PATH")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(viewModel.ytDLPStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(viewModel.ytDLPAvailable ? Color.secondary : Color.orange)
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Download Subtitles", isOn: $viewModel.subtitlesEnabled)
                    .disabled(!viewModel.subtitlesConfirmedAvailable)

                if viewModel.subtitlesEnabled {
                    if !viewModel.availableSubtitleLanguages.isEmpty {
                        HStack {
                            Text("Subtitle Language")
                                .font(.headline)
                            Picker("", selection: $viewModel.selectedSubtitleLanguage) {
                                ForEach(viewModel.availableSubtitleLanguages, id: \.self) { lang in
                                    Text(lang).tag(lang)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    } else {
                        HStack {
                            Text("Subtitle Language")
                                .font(.headline)
                            TextField("en", text: $viewModel.selectedSubtitleLanguage)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 120)
                        }
                    }

                    Toggle("Embed Subtitles in Video", isOn: $viewModel.subtitlesEmbed)
                    Text("Uses manual subtitles when available, with auto-generated fallback. Format preference: best/srt.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !viewModel.subtitlesConfirmedAvailable {
                    Text("Subtitles become available after Get Formats confirms subtitle tracks.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.hasCurrentFormats {
                Text(viewModel.formatBreakdownText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Video Format")
                        .font(.headline)
                    Picker("Video Format", selection: $viewModel.selectedVideoFormatID) {
                        if let defaultID = viewModel.defaultVideoSelectionID {
                            Text(viewModel.defaultVideoSelectionLabel).tag(Optional(defaultID))
                        } else {
                            Text("Select video format").tag(Optional<String>.none)
                        }
                        Text("Skip downloading").tag(Optional(viewModel.skipVideoSelectionID))
                        ForEach(viewModel.videoPickerFormats) { format in
                            Text(format.displayName).tag(Optional(format.id))
                        }
                    }
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Audio Format")
                        .font(.headline)
                    Picker("Audio Format", selection: $viewModel.selectedAudioFormatID) {
                        if let defaultID = viewModel.defaultAudioSelectionID {
                            Text(viewModel.defaultAudioSelectionLabel).tag(Optional(defaultID))
                        } else {
                            Text("Select audio format").tag(Optional<String>.none)
                        }
                        Text("Skip downloading").tag(Optional(viewModel.skipAudioSelectionID))
                        ForEach(viewModel.audioPickerFormats) { format in
                            Text(format.displayName).tag(Optional(format.id))
                        }
                    }
                    .pickerStyle(.menu)
                }

                Text(viewModel.selectedFormatSummary)
                    .font(.footnote)
                    .foregroundStyle(viewModel.hasExplicitFormatSelection ? Color.secondary : Color.orange)
            }

            HStack {
                if viewModel.hasCurrentFormats {
                    Button(viewModel.isFetchingFormats ? "Getting Formats..." : "Get Formats") {
                        viewModel.getFormats()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.canGetFormats)
                } else {
                    Button(viewModel.isFetchingFormats ? "Getting Formats..." : "Get Formats") {
                        viewModel.getFormats()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.canGetFormats)
                }

                if viewModel.hasCurrentFormats {
                    Button(viewModel.isDownloading ? "Cancel Download" : "Download") {
                        if viewModel.isDownloading {
                            viewModel.cancelDownload()
                        } else {
                            viewModel.runDownload()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .tint(viewModel.isDownloading ? .red : .accentColor)
                    .disabled(!viewModel.canTapDownload)
                } else {
                    Button(viewModel.isDownloading ? "Cancel Download" : "Download") {
                        if viewModel.isDownloading {
                            viewModel.cancelDownload()
                        } else {
                            viewModel.runDownload()
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(viewModel.isDownloading ? .red : .accentColor)
                    .disabled(!viewModel.canTapDownload)
                }

                Text(viewModel.state.label)
                    .foregroundStyle(statusColor(for: viewModel.state))
                    .lineLimit(2)

                Spacer()

                Button("Debug Output") {
                    openWindow(id: "debug-output")
                }
            }

            if viewModel.isDownloading, let progress = viewModel.downloadProgress {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress, total: 1.0)
                        .progressViewStyle(.linear)
                    Text("\(Int(progress * 100))%")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 6)
            } else if viewModel.isRunning {
                ProgressView()
                    .progressViewStyle(.linear)
            }

            if !viewModel.processOutput.isEmpty {
                Text(viewModel.processOutput)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
            }

            Spacer()
        }
        .padding(20)
    }

    private func statusColor(for state: DownloadState) -> Color {
        switch state {
        case .failure:
            return .red
        case .cancelled:
            return .orange
        case .success:
            return .green
        default:
            return .secondary
        }
    }

    private func pickDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func pickExecutable() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

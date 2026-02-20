import SwiftUI

struct DebugOutputView: View {
    @ObservedObject var viewModel: DownloadViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("yt-dlp Debug Output")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    viewModel.clearDebugOutput()
                }
            }

            TextEditor(text: $viewModel.debugOutput)
                .font(.system(.footnote, design: .monospaced))
                .frame(minHeight: 420)
        }
        .padding(16)
    }
}

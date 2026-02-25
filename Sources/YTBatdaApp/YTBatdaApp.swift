import SwiftUI

@main
struct ytBatdaMainApp: App {
    @StateObject private var viewModel: DownloadViewModel

    init() {
        _viewModel = StateObject(wrappedValue: DownloadViewModel(service: YTDLPService()))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 760, minHeight: 600)
        }

        WindowGroup("Debug Output", id: "debug-output") {
            DebugOutputView(viewModel: viewModel)
                .frame(minWidth: 900, minHeight: 560)
        }
    }
}

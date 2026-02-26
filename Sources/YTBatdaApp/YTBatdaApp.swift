import SwiftUI

@main
struct ytBatdaMainApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppSettings.checkForUpdatesAtLaunchKey) private var checkForUpdatesAtLaunch = true
    @StateObject private var viewModel: DownloadViewModel
    @StateObject private var updater = AppUpdater()
    @State private var didRunLaunchUpdateCheck = false

    init() {
        _viewModel = StateObject(wrappedValue: DownloadViewModel(service: YTDLPService()))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 760, minHeight: 600)
                .onChange(of: scenePhase, initial: true) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task {
                        await runLaunchUpdateCheckIfNeeded()
                    }
                }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await updater.checkForUpdates() }
                }
            }
        }

        WindowGroup("Debug Output", id: "debug-output") {
            DebugOutputView(viewModel: viewModel)
                .frame(minWidth: 900, minHeight: 560)
        }

        Settings {
            AppSettingsView()
        }
    }

    @MainActor
    private func runLaunchUpdateCheckIfNeeded() async {
        guard !didRunLaunchUpdateCheck else { return }
        didRunLaunchUpdateCheck = true

        guard checkForUpdatesAtLaunch else { return }
        await updater.checkForUpdates(userInitiated: false)
    }
}

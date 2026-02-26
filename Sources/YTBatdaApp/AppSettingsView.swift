import SwiftUI

enum AppSettings {
    static let checkForUpdatesAtLaunchKey = "checkForUpdatesAtLaunch"
}

struct AppSettingsView: View {
    @AppStorage(AppSettings.checkForUpdatesAtLaunchKey) private var checkForUpdatesAtLaunch = true

    var body: some View {
        Form {
            Toggle("Check for updates at launch", isOn: $checkForUpdatesAtLaunch)
        }
        .padding(20)
        .frame(width: 360)
    }
}

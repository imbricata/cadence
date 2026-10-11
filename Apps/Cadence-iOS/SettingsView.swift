import SwiftUI
import CadenceCore

struct SettingsView: View {
    var body: some View {
        Form {
            GoogleSettingsSection()
            Section("About") {
                LabeledContent("Version", value: "0.1.0")
            }
        }
        .navigationTitle("Settings")
    }
}
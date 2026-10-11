import SwiftUI
import CadenceCore

struct SettingsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Form {
            Section("Google") {
                Label("Not connected", systemImage: "person.crop.circle.badge.questionmark")
                    .foregroundStyle(.secondary)
            }
            Section("About") {
                LabeledContent("Version", value: "0.1.0")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }
}
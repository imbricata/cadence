import SwiftUI
import CadenceCore

struct SettingsView: View {
    var body: some View {
        Form {
            GoogleSettingsSection()
            InboxSettingsSection()
            ExportSection()
            Section("About") {
                LabeledContent("Version", value: "0.1.0")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding()
    }
}
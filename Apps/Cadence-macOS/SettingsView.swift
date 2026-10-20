import SwiftUI
import CadenceCore

struct SettingsView: View {
    var body: some View {
        TabView {
            Form {
                AccountSection()
                ClassesSection()
                SyncSection()
                AboutSection()
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            Form { AISortingSection() }
                .formStyle(.grouped)
                .tabItem { Label("AI Sorting", systemImage: "sparkles") }

            Form { ExportSection() }
                .formStyle(.grouped)
                .tabItem { Label("Data", systemImage: "externaldrive") }

            Form { AdvancedSection() }
                .formStyle(.grouped)
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 520, height: 460)
    }
}

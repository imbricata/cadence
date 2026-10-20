import SwiftUI
import SwiftData
import CadenceCore

@main
struct CadenceApp: App {
    @State private var services = AppServices.make()

    var body: some Scene {
        WindowGroup {
            RootView()
                .cadenceEnvironment(services)
                .frame(minWidth: 980, minHeight: 600)
        }
        .defaultSize(width: 1320, height: 840)

        Settings {
            SettingsView()
                .cadenceEnvironment(services)
        }
        .commands {
            CadenceCommands()
        }
    }
}
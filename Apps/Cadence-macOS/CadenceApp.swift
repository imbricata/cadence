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
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1150, height: 720)

        Settings {
            SettingsView()
                .cadenceEnvironment(services)
        }
        .commands {
            CadenceCommands()
        }
    }
}
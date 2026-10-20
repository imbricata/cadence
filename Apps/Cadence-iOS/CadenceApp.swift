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
        }
    }
}
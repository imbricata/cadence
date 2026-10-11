import SwiftUI
import SwiftData
import CadenceCore

@main
struct CadenceApp: App {
    @State private var store: AppStore
    @State private var google: GoogleService

    init() {
        let s = try! AppStore.live()
        _store = State(initialValue: s)
        _google = State(initialValue: GoogleService(store: s))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(google)
                .modelContainer(store.container)
        }
    }
}
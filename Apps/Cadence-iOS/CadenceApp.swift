import SwiftUI
import SwiftData
import CadenceCore

@main
struct CadenceApp: App {
    @State private var store: AppStore

    init() {
        let s = try! AppStore.live()
        _store = State(initialValue: s)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .modelContainer(store.container)
        }
    }
}
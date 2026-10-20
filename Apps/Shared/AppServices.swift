import SwiftUI
import SwiftData
import CadenceCore

/// Everything both apps need at launch, built once. In DEBUG builds `-CadenceDemo YES` swaps in fixtures.
@MainActor
struct AppServices {
    let store: AppStore
    let google: GoogleService
    let inbox: InboxService
    let insights: InsightsModel

    static func make() -> AppServices {
        #if DEBUG
        if DemoMode.isEnabled { return DemoMode.makeServices() }
        #endif
        let store = try! AppStore.live()
        let google = GoogleService(store: store)
        return AppServices(store: store, google: google, inbox: InboxService(store: store), insights: InsightsModel(store: store, events: google.eventStore))
    }
}

extension View {
    func cadenceEnvironment(_ s: AppServices) -> some View {
        self
            .environment(s.store)
            .environment(s.google)
            .environment(s.inbox)
            .environment(s.insights)
            .modelContainer(s.store.container)
    }
}

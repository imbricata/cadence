import SwiftUI
import CadenceCore

struct RootView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "calendar") }
            InboxView()
                .tabItem { Label("Inbox", systemImage: "tray") }
            AreasView()
                .tabItem { Label("Areas", systemImage: "square.grid.2x2") }
        }
    }
}

#if DEBUG
#Preview {
    RootView()
        .environment(try! AppStore.inMemory())
        .modelContainer(try! AppStore.inMemory().container)
}
#endif
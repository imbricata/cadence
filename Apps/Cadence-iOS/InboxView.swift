import SwiftUI
import CadenceCore

struct InboxView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Inbox",
                systemImage: "tray",
                description: Text("Capture quick notes here; they'll be sorted into items later.")
            )
            .navigationTitle("Inbox")
        }
    }
}
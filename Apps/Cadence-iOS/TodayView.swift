import SwiftUI
import CadenceCore

struct TodayView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No blocks yet",
                systemImage: "calendar",
                description: Text("Your day's timeline will appear here once you connect Google Calendar.")
            )
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
    }
}
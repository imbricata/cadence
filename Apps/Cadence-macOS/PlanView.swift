import SwiftUI
import CadenceCore

struct PlanView: View {
    var body: some View {
        ContentUnavailableView(
            "Plan your day",
            systemImage: "calendar",
            description: Text("Drag items onto blocks here once you connect Google Calendar.")
        )
        .navigationTitle("Plan")
    }
}
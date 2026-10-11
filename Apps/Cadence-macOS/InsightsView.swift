import SwiftUI
import CadenceCore

struct InsightsView: View {
    var body: some View {
        ContentUnavailableView(
            "Insights",
            systemImage: "chart.bar",
            description: Text("Form per area, follow-through, and hours will appear once you've logged some time.")
        )
        .navigationTitle("Insights")
    }
}
import SwiftUI
import CadenceCore

struct TargetSection: View {
    @Environment(AppStore.self) private var store
    let area: Area
    var daysObserved: Int = 0
    var hasTarget: Bool = false
    var targetWeeklyMinutes: Int? = nil

    @State private var showEdit = false

    private var promptedKey: String { "target.prompted.\(area.id.uuidString)" }
    private var wasPrompted: Bool { UserDefaults.standard.bool(forKey: promptedKey) }

    var body: some View {
        Section("Target") {
            if hasTarget, let t = targetWeeklyMinutes {
                HStack {
                    Text("\(t) min/week").monospacedDigit()
                    Spacer()
                    Button("Edit") { showEdit = true }
                }
            } else if daysObserved >= ScoringConfig.targetProposalDays && !wasPrompted {
                VStack(alignment: .leading, spacing: 8) {
                    if let median = proposeTarget(weeklyMinutes: weeklyMinuteTotals(areaId: area.id, context: store.context)) {
                        Text("Based on your recent weeks, a weekly target of \(median) minutes would be a good starting point.")
                            .font(.callout)
                    }
                    HStack {
                        if let median = proposeTarget(weeklyMinutes: weeklyMinuteTotals(areaId: area.id, context: store.context)) {
                            Button("Set \(median) min") {
                                upsertTarget(store, areaId: area.id, weeklyMinutes: median, weeklySessions: nil)
                                rememberPrompt()
                            }
                        }
                        Button("Edit") { showEdit = true }
                        Button("Skip") { rememberPrompt() }
                    }
                }
            } else {
                HStack {
                    Text("No weekly target")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Set") { showEdit = true }
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            TargetEditSheet(area: area, current: targetWeeklyMinutes, onClose: { rememberPrompt() })
        }
    }

    private func rememberPrompt() {
        UserDefaults.standard.set(true, forKey: promptedKey)
    }
}

struct TargetEditSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let area: Area
    let current: Int?
    var onClose: () -> Void

    @State private var minutes: Int = 150
    @State private var has = true

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Weekly minutes target", isOn: $has)
                if has {
                    Stepper("\(minutes) min", value: $minutes, in: 15...3000, step: 15)
                }
            }
            .navigationTitle("Target · \(area.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        upsertTarget(store, areaId: area.id, weeklyMinutes: has ? minutes : nil, weeklySessions: nil)
                        onClose()
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let current { minutes = current; has = true } else { has = current != nil }
            }
        }
    }
}
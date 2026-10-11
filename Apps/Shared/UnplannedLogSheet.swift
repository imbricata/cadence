import SwiftUI
import SwiftData
import CadenceCore

struct UnplannedLogSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Area.sortOrder) private var areas: [Area]
    @Query private var items: [Item]

    @State private var areaId: UUID?
    @State private var itemId: UUID?
    @State private var outcome: LogOutcome = .full
    @State private var minutes: Int = 30
    @State private var note: String = ""
    @State private var date: Date = .now

    private var selectableAreas: [Area] {
        areas.filter { !$0.isDeleted && !$0.isArchived && !$0.isClassesCalendar }
    }
    private var areaItems: [Item] {
        guard let areaId else { return [] }
        return items.filter { !$0.isDeleted && $0.areaId == areaId }.sorted { $0.title < $1.title }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Area") {
                    Picker("Area", selection: $areaId) {
                        Text("Choose…").tag(UUID?.none)
                        ForEach(selectableAreas) { area in
                            Text(area.name).tag(Optional(area.id))
                        }
                    }
                }
                Section("What") {
                    Picker("Item", selection: $itemId) {
                        Text("None").tag(UUID?.none)
                        ForEach(areaItems) { item in
                            Text(item.title).tag(Optional(item.id))
                        }
                    }
                    Picker("Outcome", selection: $outcome) {
                        Text("Full").tag(LogOutcome.full)
                        Text("Easy").tag(LogOutcome.easy)
                        Text("Skipped").tag(LogOutcome.skipped)
                    }
                    .pickerStyle(.segmented)
                    Stepper("\(minutes) min", value: $minutes, in: 5...600, step: 5)
                }
                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Log time")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(areaId == nil)
                }
            }
            .onAppear {
                if areaId == nil { areaId = selectableAreas.first?.id }
            }
        }
    }

    private func save() {
        guard let areaId else { return }
        addUnplannedLog(store, areaId: areaId, itemId: itemId, date: date, outcome: outcome,
                        minutes: minutes, note: note.isEmpty ? nil : note)
        if let itemId {
            applyOutcomeToTask(store, itemId: itemId, outcome: outcome)
        }
        dismiss()
    }
}
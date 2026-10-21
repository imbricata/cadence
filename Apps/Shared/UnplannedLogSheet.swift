import SwiftUI
import SwiftData
import CadenceCore

/// Log time you spent without a block.
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
        return items.filter { !$0.isDeleted && $0.areaId == areaId && !($0.kind == .task && $0.status != .open) }.sorted { $0.title < $1.title }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Area") {
                    ChipFlow {
                        ForEach(selectableAreas) { a in
                            AreaChip(title: a.name, colorHex: a.colorHex, isOn: areaId == a.id) {
                                areaId = a.id
                                itemId = nil
                            }
                        }
                    }
                    .padding(.vertical, Theme.Space.xs)
                }
                Section {
                    Picker("Item", selection: $itemId) {
                        Text("None").tag(UUID?.none)
                        ForEach(areaItems) { Text($0.title).tag(Optional($0.id)) }
                    }
                    Picker("Outcome", selection: $outcome) {
                        Label("Full", systemImage: OutcomeStyle.symbol(LogOutcome.full)).tag(LogOutcome.full)
                        Label("Easy", systemImage: OutcomeStyle.symbol(LogOutcome.easy)).tag(LogOutcome.easy)
                    }
                    .pickerStyle(.segmented)
                    LabeledContent("Time") { MinutesField(minutes: $minutes, range: 5...600) }
                    DatePicker("When", selection: $date)
                }
                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Log time")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(areaId == nil) }
            }
            .onAppear { if areaId == nil { areaId = selectableAreas.first?.id } }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 480)
        #endif
    }

    private func save() {
        guard let areaId else { return }
        addUnplannedLog(store, areaId: areaId, itemId: itemId, date: date, outcome: outcome,
                        minutes: minutes, note: note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note)
        if let itemId, outcome == .full { applyOutcomeToTask(store, itemId: itemId, outcome: .full) }
        dismiss()
    }
}

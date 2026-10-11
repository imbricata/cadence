import SwiftUI
import CadenceCore

struct ItemEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let areaId: UUID
    let item: Item?

    @State private var title: String
    @State private var kind: ItemKind
    @State private var hasDue: Bool
    @State private var dueDate: Date
    @State private var fullVersion: String
    @State private var easyVersion: String
    @State private var notes: String

    init(areaId: UUID, item: Item? = nil) {
        self.areaId = areaId
        self.item = item
        _title = State(initialValue: item?.title ?? "")
        _kind = State(initialValue: item?.kind ?? .task)
        _hasDue = State(initialValue: item?.dueDate != nil)
        _dueDate = State(initialValue: item?.dueDate ?? .now)
        _fullVersion = State(initialValue: item?.fullVersion ?? "")
        _easyVersion = State(initialValue: item?.easyVersion ?? "")
        _notes = State(initialValue: item?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    Picker("Kind", selection: $kind) {
                        Text("Task").tag(ItemKind.task)
                        Text("Activity").tag(ItemKind.activity)
                    }
                    .pickerStyle(.segmented)
                }
                if kind == .task {
                    Section {
                        Toggle("Due date", isOn: $hasDue)
                        if hasDue {
                            DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                        }
                    }
                }
                Section("Versions") {
                    TextField("Full version (optional)", text: $fullVersion)
                    TextField("Easy version (optional)", text: $easyVersion)
                }
                Section("Notes") {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle(item == nil ? "New Item" : "Edit Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespaces)
        let due: Date? = (kind == .task && hasDue) ? Calendar.current.startOfDay(for: dueDate) : nil
        if let item {
            updateItem(store, item,
                       title: t, kind: kind,
                       dueDate: due as Date?,
                       fullVersion: fullVersion.isEmpty ? nil : fullVersion,
                       easyVersion: easyVersion.isEmpty ? nil : easyVersion,
                       notes: notes.isEmpty ? nil : notes)
        } else {
            let it = createItem(store, kind: kind, title: t, areaId: areaId, dueDate: due)
            if !fullVersion.isEmpty || !easyVersion.isEmpty || !notes.isEmpty {
                updateItem(store, it,
                           fullVersion: fullVersion.isEmpty ? nil : fullVersion,
                           easyVersion: easyVersion.isEmpty ? nil : easyVersion,
                           notes: notes.isEmpty ? nil : notes)
            }
        }
        dismiss()
    }
}
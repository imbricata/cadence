import SwiftUI
import SwiftData
import CadenceCore

/// Create or edit a task / activity. Autosave is not used here: Save commits, Cancel discards.
struct ItemEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(GoogleService.self) private var google
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Area.sortOrder) private var allAreas: [Area]

    let item: Item?

    @State private var areaId: UUID?
    @State private var title: String
    @State private var kind: ItemKind
    @State private var status: ItemStatus
    @State private var hasDue: Bool
    @State private var dueDate: Date
    @State private var fullVersion: String
    @State private var easyVersion: String
    @State private var notes: String
    @FocusState private var titleFocused: Bool

    init(areaId: UUID? = nil, item: Item? = nil) {
        self.item = item
        _areaId = State(initialValue: item?.areaId ?? areaId)
        _title = State(initialValue: item?.title ?? "")
        _kind = State(initialValue: item?.kind ?? .task)
        _status = State(initialValue: item?.status ?? .open)
        _hasDue = State(initialValue: item?.dueDate != nil)
        _dueDate = State(initialValue: item?.dueDate ?? .now)
        _fullVersion = State(initialValue: item?.fullVersion ?? "")
        _easyVersion = State(initialValue: item?.easyVersion ?? "")
        _notes = State(initialValue: item?.notes ?? "")
    }

    private var areas: [Area] { allAreas.filter { !$0.isDeleted && !$0.isArchived && !$0.isClassesCalendar } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Area") {
                    ChipFlow {
                        ForEach(areas) { area in
                            AreaChip(title: area.name, colorHex: area.colorHex, isOn: area.id == areaId) { areaId = area.id }
                        }
                    }
                    .padding(.vertical, Theme.Space.xs)
                }
                Section {
                    TextField("Title", text: $title)
                        .focused($titleFocused)
                    Picker("Kind", selection: $kind) {
                        Text("Task").tag(ItemKind.task)
                        Text("Activity").tag(ItemKind.activity)
                    }
                    .pickerStyle(.segmented)
                }
                if kind == .task {
                    Section {
                        Toggle("Due date", isOn: $hasDue)
                        if hasDue { DatePicker("Due", selection: $dueDate, displayedComponents: .date) }
                        if item != nil {
                            Picker("Status", selection: $status) {
                                Text("Open").tag(ItemStatus.open)
                                Text("Done").tag(ItemStatus.done)
                                Text("Dropped").tag(ItemStatus.dropped)
                            }
                        }
                    }
                }
                Section {
                    TextField("Full version", text: $fullVersion)
                    TextField("Easy version", text: $easyVersion)
                } header: {
                    Text("Versions")
                } footer: {
                    Text("Optional. Shown when you log the item as Full or Easy.")
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                if item != nil {
                    Section {
                        Button("Delete", role: .destructive, action: deleteItemAndDismiss)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(item == nil ? "New Item" : "Edit Item")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !areas.contains { $0.id == areaId })
                }
            }
            .onAppear {
                if areaId == nil { areaId = areas.first?.id }
                if item == nil { titleFocused = true }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 540)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let areaId, areas.contains(where: { $0.id == areaId }) else { return }
        let due: Date? = (kind == .task && hasDue) ? Calendar.current.startOfDay(for: dueDate) : nil
        func opt(_ s: String) -> String? { s.trimmingCharacters(in: .whitespaces).isEmpty ? nil : s }
        if let item {
            updateItem(store, item, title: t, kind: kind, areaId: areaId, dueDate: due as Date?,
                       fullVersion: opt(fullVersion), easyVersion: opt(easyVersion), notes: opt(notes),
                       status: kind == .task ? status : .open)
        } else {
            let it = createItem(store, kind: kind, title: t, areaId: areaId, dueDate: due)
            updateItem(store, it, fullVersion: opt(fullVersion), easyVersion: opt(easyVersion), notes: opt(notes))
        }
        dismiss()
    }

    private func deleteItemAndDismiss() {
        guard let item else { return }
        let name = item.title
        deleteItem(store, item)
        google.message = UserMessage("Deleted “\(name)”", actionTitle: "Undo") {
            item.isDeleted = false
            item.updatedAt = .now
            store.save()
        }
        dismiss()
    }
}

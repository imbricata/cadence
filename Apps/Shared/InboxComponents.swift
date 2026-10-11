import SwiftUI
import SwiftData
import CadenceCore

struct InboxNoteRow: View {
    @Environment(AppStore.self) private var store
    @Environment(InboxService.self) private var inbox

    let note: InboxNote
    let item: Item?
    let area: Area?

    @State private var showEditor = false
    @State private var showManual = false

    var body: some View {
        switch note.state {
        case .pending:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Sorting…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        case .failed:
            HStack {
                Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
                Text("Couldn't sort automatically")
                    .font(.subheadline)
                Spacer()
                Button("Sort manually") { showManual = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.vertical, 4)
            .contextMenu {
                Button("Re-sort") { Task { await inbox.resort(note) } }
                Button("Delete", role: .destructive) { deleteInboxNote(store, note) }
            }
            .sheet(isPresented: $showManual) { ManualSortSheet(note: note) }
        case .sorted:
            Button { showEditor = true } label: {
                HStack(spacing: 10) {
                    AreaColorDot(colorHex: area?.colorHex ?? "#888C96", size: 10)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item?.title ?? "")
                            .font(.subheadline)
                        HStack(spacing: 6) {
                            Text(item?.kind == .activity ? "Activity" : "Task")
                                .font(.caption2).foregroundStyle(.secondary)
                            if let due = item?.dueDate {
                                Text(due, format: .dateTime.month(.abbreviated).day())
                                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Edit") { showEditor = true }
                Button("Re-sort") { Task { await inbox.resort(note) } }
                Button("Delete", role: .destructive) { deleteInboxNote(store, note) }
            }
            .sheet(isPresented: $showEditor) {
                if let item {
                    ItemEditorView(areaId: item.areaId, item: item)
                }
            }
        }
    }
}

struct ManualSortSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Area.sortOrder) private var areas: [Area]

    let note: InboxNote

    @State private var areaId: UUID?
    @State private var kind: ItemKind = .task
    @State private var title: String = ""

    private var selectable: [Area] {
        areas.filter { !$0.isDeleted && !$0.isArchived && !$0.isClassesCalendar }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Area", selection: $areaId) {
                    Text("Choose…").tag(UUID?.none)
                    ForEach(selectable) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("Kind", selection: $kind) {
                    Text("Task").tag(ItemKind.task)
                    Text("Activity").tag(ItemKind.activity)
                }
                .pickerStyle(.segmented)
                TextField("Title", text: $title)
            }
            .navigationTitle("Sort manually")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                        .disabled(areaId == nil || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { if areaId == nil { areaId = selectable.first?.id } }
        }
    }

    private func save() {
        guard let areaId else { return }
        let item = createItem(store, kind: kind, title: title.trimmingCharacters(in: .whitespaces), areaId: areaId)
        completeManually(store, note, itemId: item.id)
        dismiss()
    }
}

struct InboxSettingsSection: View {
    @Environment(InboxService.self) private var inbox

    @State private var key: String = ""
    @State private var model: String = ""
    @State private var cap: Double = 1.0

    var body: some View {
        Section("OpenRouter (AI sorting)") {
            SecureField("API key", text: $key)
                .onAppear { key = inbox.currentKey }
                .onSubmit { inbox.setKey(key) }

            TextField("Model", text: $model)
                .onAppear { model = inbox.model }
                .onSubmit { inbox.setModel(model) }

            Stepper(value: $cap, in: 0.25...20, step: 0.25) {
                Text("Monthly cap: $\(String(format: "%.2f", cap))")
            }
            .onChange(of: cap) { _, v in inbox.setCap(v) }
            .onAppear { cap = inbox.monthlyCapUSD }

            LabeledContent("This month", value: "$\(String(format: "%.3f", inbox.monthCostUSD))")
                .monospacedDigit()
            if inbox.isOverCap {
                Label("Monthly cap reached — sorting paused", systemImage: "pause.circle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }
}
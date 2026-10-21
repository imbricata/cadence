import SwiftUI
import SwiftData
import CadenceCore

/// One note in the Inbox: sorting, failed, or a compact item card. The raw text is never shown.
struct InboxNoteRow: View {
    @Environment(AppStore.self) private var store
    @Environment(InboxService.self) private var inbox

    let note: InboxNote
    let item: Item?
    let area: Area?
    var onEdit: (Item) -> Void

    @State private var showManual = false

    var body: some View {
        Group {
            switch note.state {
            case .pending: pending
            case .failed: failed
            case .sorted: sorted
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            if let item { Button("Edit…") { onEdit(item) } }
            if note.state != .pending { Button("Sort Again") { Task { await inbox.resort(note) } } }
            Button("Delete", role: .destructive) { deleteInboxCard(store, note) }
        }
        .sheet(isPresented: $showManual) { ManualSortSheet(note: note) }
    }

    private var pending: some View {
        HStack(spacing: Theme.Space.s) {
            ProgressView().controlSize(.small)
            Text("Sorting…").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var failed: some View {
        HStack {
            Image(systemName: "exclamationmark.circle").foregroundStyle(.secondary)
            Text("Couldn't sort this note").font(.subheadline)
            Spacer()
            Button("Sort") { showManual = true }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private var sorted: some View {
        if let item {
            Button { onEdit(item) } label: {
                HStack(spacing: Theme.Space.m) {
                    AreaDot(colorHex: area?.colorHex ?? "#888C96", size: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.body).lineLimit(2).multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            Text(subtitle(item)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            if note.isLowConfidence {
                                Image(systemName: "questionmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .accessibilityLabel("Low confidence. Check the area.")
                                    .help("Not sure about this one. Check the area.")
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Text("Removed").font(.subheadline).foregroundStyle(.tertiary)
        }
    }

    private func subtitle(_ item: Item) -> String {
        let name = area?.name ?? ""
        switch item.kind {
        case .activity: return "\(name) · Activity"
        case .task:
            if let due = item.dueDate { return "\(name) · Task · Due \(due.formatted(.dateTime.day().month(.abbreviated)))" }
            return "\(name) · Task"
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
                Section("Area") {
                    ChipFlow {
                        ForEach(selectable) { a in
                            AreaChip(title: a.name, colorHex: a.colorHex, isOn: areaId == a.id) { areaId = a.id }
                        }
                    }
                    .padding(.vertical, Theme.Space.xs)
                }
                Section {
                    TextField("Title", text: $title)
                    Picker("Kind", selection: $kind) {
                        Text("Task").tag(ItemKind.task)
                        Text("Activity").tag(ItemKind.activity)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Sort note")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                        .disabled(areaId == nil || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if areaId == nil { areaId = selectable.first?.id }
                if title.isEmpty { title = note.rawText }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 340)
        #else
        .presentationDetents([.medium])
        #endif
    }

    private func save() {
        guard let areaId else { return }
        let item = createItem(store, kind: kind, title: title.trimmingCharacters(in: .whitespaces), areaId: areaId)
        completeManually(store, note, itemId: item.id)
        dismiss()
    }
}

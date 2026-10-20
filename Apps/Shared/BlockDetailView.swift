import SwiftUI
import SwiftData
import CadenceCore

/// One block: plan what goes in it (autosaved, never counts as work) and, separately, log how it went.
/// Opening this view never writes anything.
struct BlockDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    enum Presentation { case sheet, popover }

    let event: CalendarEvent
    let area: Area
    var presentation: Presentation = .sheet

    @Query private var items: [Item]
    @Query private var logs: [BlockLog]
    @Query private var allEntries: [BlockEntry]

    @State private var note = ""
    @State private var noteLoaded = false

    private var ref: BlockRef { BlockRef(event: event, areaId: area.id) }

    private var log: BlockLog? {
        logs.first { !$0.isDeleted && $0.googleEventId == event.id && $0.eventStart == event.start }
    }
    private var state: BlockLogState { log?.state ?? .unlogged }

    private var entries: [BlockEntry] {
        guard let log else { return [] }
        return allEntries
            .filter { !$0.isDeleted && $0.blockLogId == log.id }
            .sorted { (title(of: $0) ?? "") < (title(of: $1) ?? "") }
    }

    private var plannedItemIds: Set<UUID> { Set(entries.compactMap(\.itemId)) }

    private var areaItems: [Item] { items.filter { !$0.isDeleted && $0.areaId == area.id } }
    private var addableActivities: [Item] {
        areaItems.filter { $0.kind == .activity && !plannedItemIds.contains($0.id) }.sorted { $0.title < $1.title }
    }
    private var addableTasks: [Item] {
        areaItems.filter { $0.kind == .task && $0.status == .open && !plannedItemIds.contains($0.id) }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private var stateBinding: Binding<BlockLogState> {
        Binding(
            get: { state },
            set: { logBlock(store, ref, state: $0) }
        )
    }

    var body: some View {
        switch presentation {
        case .sheet:
            NavigationStack {
                form
                    .navigationTitle(event.summary.isEmpty ? area.name : event.summary)
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { commitNote(); dismiss() } }
                    }
            }
        case .popover:
            VStack(spacing: 0) {
                HStack(spacing: Theme.Space.s) {
                    AreaDot(colorHex: area.colorHex)
                    Text(event.summary.isEmpty ? area.name : event.summary).font(.headline).lineLimit(1)
                    Spacer()
                    Button("Done") { commitNote(); dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(Theme.Space.l)
                Divider()
                form
            }
            .frame(width: 380)
            .frame(minHeight: 320, maxHeight: 560)
        }
    }

    private var form: some View {
        Form {
                Section {
                    LabeledContent("When") {
                        Text("\(event.start.formatted(.dateTime.weekday(.abbreviated).day().month())) · \(event.start.formatted(date: .omitted, time: .shortened))–\(event.end.formatted(date: .omitted, time: .shortened))")
                            .monospacedDigit()
                    }
                }

                Section("In this block") {
                    if entries.isEmpty {
                        Text("Nothing planned yet. Add items below, or leave it empty to log the block on its own.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(entries) { entry in
                        entryRow(entry)
                    }
                    if !addableActivities.isEmpty || !addableTasks.isEmpty {
                        addMenu
                    }
                }

                Section {
                    Picker("Outcome", selection: stateBinding) {
                        Text("Not yet").tag(BlockLogState.unlogged)
                        Text("Full").tag(BlockLogState.full)
                        Text("Easy").tag(BlockLogState.easy)
                        Text("Skipped").tag(BlockLogState.skipped)
                    }
                    .pickerStyle(.segmented)
                    .sensoryFeedback(.selection, trigger: state)

                    if let log, entries.isEmpty, state == .full || state == .easy {
                        Stepper(value: Binding(get: { log.loggedMinutes }, set: { setBlockMinutes(store, log, minutes: $0) }), in: 0...600, step: 5) {
                            Text("\(log.loggedMinutes) min").monospacedDigit()
                        }
                    }
                    if state != .unlogged {
                        TextField("Note", text: $note, axis: .vertical)
                            .onSubmit(commitNote)
                    }
                } header: {
                    Text("How it went")
                } footer: {
                    if state == .unlogged { Text("Log it when you're done. Planning alone never counts.") }
                }

                if state != .unlogged, let log {
                    Section {
                        Button("Clear log", role: .destructive) { clearBlockLog(store, log); note = "" }
                    }
                }
            }
        .formStyle(.grouped)
        .onAppear {
            guard !noteLoaded else { return }
            noteLoaded = true
            note = log?.note ?? ""
        }
        .onDisappear(perform: commitNote)
    }

    // MARK: - Rows

    @ViewBuilder
    private func entryRow(_ entry: BlockEntry) -> some View {
        let item = items.first { $0.id == entry.itemId }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item?.title ?? "Removed item")
                Spacer()
                if state != .unlogged {
                    Picker("Outcome", selection: Binding(
                        get: { entry.outcome == .planned ? LogOutcome(state) : entry.outcome },
                        set: { setEntryOutcome(store, entry, outcome: $0, blockMinutes: log?.plannedMinutes ?? ref.plannedMinutes) }
                    )) {
                        Text("Full").tag(LogOutcome.full)
                        Text("Easy").tag(LogOutcome.easy)
                        Text("Skipped").tag(LogOutcome.skipped)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                Button {
                    if let id = entry.itemId { unplanItem(store, itemId: id, in: ref) }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove from block")
            }
            if let hint = versionHint(item, entry) {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            if state != .unlogged, entry.outcome.countsAsWork {
                Stepper(value: Binding(get: { entry.minutes }, set: { setEntryMinutes(store, entry, minutes: $0) }), in: 0...600, step: 5) {
                    Text("\(entry.minutes) min").monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var addMenu: some View {
        Menu {
            if !addableActivities.isEmpty {
                Section("Activities") {
                    ForEach(addableActivities) { item in
                        Button(item.title) { planItem(store, item: item, in: ref) }
                    }
                }
            }
            if !addableTasks.isEmpty {
                Section("Tasks") {
                    ForEach(addableTasks) { item in
                        Button(item.title) { planItem(store, item: item, in: ref) }
                    }
                }
            }
        } label: {
            Label("Add item", systemImage: "plus")
        }
    }

    // MARK: - Helpers

    private func title(of entry: BlockEntry) -> String? {
        items.first { $0.id == entry.itemId }?.title
    }

    private func versionHint(_ item: Item?, _ entry: BlockEntry) -> String? {
        guard let item else { return nil }
        switch entry.outcome {
        case .easy: return item.easyVersion
        case .planned, .full: return item.fullVersion
        case .skipped: return nil
        }
    }

    private func commitNote() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let log {
            if (log.note ?? "") != trimmed { setBlockNote(store, log, note: trimmed) }
        }
    }
}

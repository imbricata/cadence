import SwiftUI
import SwiftData
import CadenceCore

struct BlockChosenEntry: Identifiable {
    let id = UUID()
    let item: Item
    var outcome: LogOutcome
    var minutes: Int
}

struct BlockFillLogView: View {
    @Environment(AppStore.self) private var store
    @Environment(GoogleService.self) private var google
    @Environment(\.dismiss) private var dismiss

    let event: CalendarEvent
    let area: Area

    @Query private var items: [Item]

    @State private var log: BlockLog?
    @State private var entries: [BlockChosenEntry] = []
    @State private var outcome: BlockLogState = .full
    @State private var minutes: Int = 0
    @State private var note: String = ""
    @State private var loaded = false

    private var activities: [Item] {
        items.filter { !$0.isDeleted && $0.kind == .activity && $0.areaId == area.id }.sorted { $0.title < $1.title }
    }
    private var openTasks: [Item] {
        items.filter { !$0.isDeleted && $0.kind == .task && $0.status == .open && $0.areaId == area.id }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private var plannedMinutes: Int {
        max(1, Int(event.end.timeIntervalSince(event.start) / 60))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("This block") {
                    Picker("Outcome", selection: $outcome) {
                        Text("Full").tag(BlockLogState.full)
                        Text("Easy").tag(BlockLogState.easy)
                        Text("Skipped").tag(BlockLogState.skipped)
                    }
                    .pickerStyle(.segmented)
                    Stepper("\(minutes) min", value: $minutes, in: 0...600, step: 5)
                    TextField("Note", text: $note, axis: .vertical)
                }

                if !activities.isEmpty {
                    Section("Activities") {
                        chips(activities) { toggleAdd($0) }
                    }
                }
                if !openTasks.isEmpty {
                    Section("Tasks") {
                        ForEach(openTasks) { item in
                            Button { toggleAdd(item) } label: {
                                HStack {
                                    Image(systemName: isAdded(item) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isAdded(item) ? Color(hex: area.colorHex) : Color.secondary)
                                    Text(item.title)
                                    Spacer()
                                }
                            }
                        }
                    }
                }

                if !entries.isEmpty {
                    Section("Logged") {
                        ForEach($entries) { $entry in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(entry.item.title).font(.callout)
                                    Spacer()
                                    Button { remove(entry.item) } label: {
                                        Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                Picker("Outcome", selection: $entry.outcome) {
                                    Text("Full").tag(LogOutcome.full)
                                    Text("Easy").tag(LogOutcome.easy)
                                    Text("Skipped").tag(LogOutcome.skipped)
                                }
                                .pickerStyle(.segmented)
                                HStack {
                                    Text("Minutes").font(.subheadline).foregroundStyle(.secondary)
                                    Stepper("\(entry.minutes)", value: $entry.minutes, in: 0...600, step: 5)
                                        .labelsHidden()
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle(event.summary.isEmpty ? area.name : event.summary)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear { load() }
        }
    }

    private func chips(_ list: [Item], action: @escaping (Item) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], spacing: 8) {
            ForEach(list) { item in
                Button { action(item) } label: {
                    Text(item.title)
                        .font(.footnote)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(Capsule().fill(isAdded(item) ? Color(hex: area.colorHex).opacity(0.25) : Color.secondary.opacity(0.12)))
                        .foregroundStyle(isAdded(item) ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func isAdded(_ item: Item) -> Bool {
        entries.contains { $0.item.id == item.id }
    }

    private func toggleAdd(_ item: Item) {
        if let idx = entries.firstIndex(where: { $0.item.id == item.id }) {
            entries.remove(at: idx)
        } else {
            let share = max(5, plannedMinutes / (entries.count + 1))
            entries.append(BlockChosenEntry(item: item, outcome: .full, minutes: share))
        }
    }

    private func remove(_ item: Item) {
        entries.removeAll { $0.item.id == item.id }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let existing = ensureBlockLog(store, googleEventId: event.id, eventStart: event.start, areaId: area.id, plannedMinutes: plannedMinutes)
        log = existing
        minutes = existing.loggedMinutes > 0 ? existing.loggedMinutes : plannedMinutes
        note = existing.note ?? ""
        if existing.state != .unlogged { outcome = existing.state }
        for e in blockEntries(forLogId: existing.id, in: store.context) {
            if let item = items.first(where: { $0.id == e.itemId }) {
                entries.append(BlockChosenEntry(item: item, outcome: e.outcome, minutes: e.minutes))
            }
        }
    }

    private func save() {
        guard let log else { return }
        updateBlockLog(store, log, state: outcome, loggedMinutes: minutes, plannedMinutes: plannedMinutes, note: note.isEmpty ? nil : note)

        for existing in blockEntries(forLogId: log.id, in: store.context) {
            existing.isDeleted = true
            existing.updatedAt = .now
        }
        for entry in entries {
            upsertEntry(store, blockLogId: log.id, itemId: entry.item.id, outcome: entry.outcome, minutes: entry.minutes)
            applyOutcomeToTask(store, itemId: entry.item.id, outcome: entry.outcome)
        }
        store.save()
        dismiss()
    }
}
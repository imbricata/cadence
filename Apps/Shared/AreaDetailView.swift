import SwiftUI
import SwiftData
import CadenceCore

struct AreaDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(GoogleService.self) private var google
    @Environment(InsightsModel.self) private var insights
    let area: Area

    @Query private var items: [Item]
    @Query private var logs: [BlockLog]
    @Query private var entries: [BlockEntry]
    @Query private var unplanned: [UnplannedLog]

    @State private var showingNew = false
    @State private var showingEdit = false
    @State private var editingItem: Item?

    private var areaItems: [Item] { items.filter { !$0.isDeleted && $0.areaId == area.id } }
    private var activities: [Item] { areaItems.filter { $0.kind == .activity }.sorted { $0.title < $1.title } }
    private var openTasks: [Item] { areaItems.filter { $0.kind == .task && $0.status == .open }.sorted(by: taskOrder) }
    private var doneTasks: [Item] {
        areaItems.filter { $0.kind == .task && $0.status != .open }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }
    private var stat: AreaStat? { insights.area(area.id) }

    var body: some View {
        List {
            Section { header }
                .listRowSeparator(.hidden)

            if !activities.isEmpty {
                Section("Activities") {
                    ForEach(activities) { item in
                        Button { editingItem = item } label: {
                            HStack {
                                Text(item.title)
                                Spacer()
                                if let s = insights.activity(item.id), s.rawMinutes > 0 {
                                    Text(s.level > 0 ? "\(Format.hours(minutes: s.rawMinutes)) · Level \(s.level)" : Format.hours(minutes: s.rawMinutes))
                                        .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Open tasks") {
                if openTasks.isEmpty { Text("Nothing open.").foregroundStyle(.secondary) }
                ForEach(openTasks) { item in
                    HStack(spacing: Theme.Space.m) {
                        Button { complete(item) } label: { Image(systemName: "circle").font(.title3).foregroundStyle(.secondary) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Mark done")
                        Button { editingItem = item } label: {
                            HStack {
                                Text(item.title)
                                Spacer()
                                if let d = item.dueDate { dueLabel(d) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            let recent = recentLogs
            if !recent.isEmpty {
                Section("Recent") {
                    ForEach(recent) { r in
                        HStack(spacing: Theme.Space.m) {
                            Image(systemName: OutcomeStyle.symbol(r.outcome)).foregroundStyle(area.color.base).frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.label).lineLimit(1)
                                Text(r.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if r.minutes > 0 { Text(Format.duration(minutes: r.minutes)).font(.callout).monospacedDigit().foregroundStyle(.secondary) }
                        }
                    }
                }
            }

            if !doneTasks.isEmpty {
                Section {
                    DisclosureGroup("Done (\(doneTasks.count))") {
                        ForEach(doneTasks) { item in
                            Text(item.title).foregroundStyle(.secondary)
                                .swipeActions { Button("Reopen") { updateItem(store, item, status: .open) } }
                                .contextMenu { Button("Reopen") { updateItem(store, item, status: .open) } }
                        }
                    }
                }
            }

            TargetSection(area: area, daysObserved: stat?.daysObserved ?? 0, hasTarget: stat?.hasTarget ?? false, targetWeeklyMinutes: stat?.targetWeeklyMinutes)
        }
        .navigationTitle(area.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingEdit = true } label: { Label("Edit Area", systemImage: "pencil") }
                    .help("Edit area")
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: { Label("Add Item", systemImage: "plus") }
                    .help("Add item")
            }
        }
        .sheet(isPresented: $showingNew) { ItemEditorView(areaId: area.id) }
        .sheet(isPresented: $showingEdit) { AreaEditorView(area: area) }
        .sheet(item: $editingItem) { ItemEditorView(areaId: area.id, item: $0) }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                if let p = stat?.formPercent {
                    Text("\(Int(p.rounded()))%").font(.system(size: 40, weight: .semibold)).monospacedDigit()
                    Text("form").foregroundStyle(.secondary)
                } else {
                    Text("Calibrating").font(.title2.weight(.semibold)).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.hours(minutes: stat?.rawMinutes ?? 0)).font(.headline).monospacedDigit()
                    Text("logged").font(.caption).foregroundStyle(.secondary)
                }
            }
            FormBar(percent: stat?.formPercent, colorHex: area.colorHex)
            if let t = stat?.targetWeeklyMinutes {
                Text("Target \(Format.duration(minutes: t)) a week").font(.footnote).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.vertical, Theme.Space.xs)
    }

    @ViewBuilder
    private func dueLabel(_ d: Date) -> some View {
        if d < Calendar.current.startOfDay(for: .now) {
            Text("Overdue").font(.caption).foregroundStyle(.orange.opacity(0.9))
        } else {
            Text(d, format: .dateTime.day().month(.abbreviated)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    // MARK: Recent logs

    private struct RecentLog: Identifiable {
        let id: UUID
        let date: Date
        let label: String
        let outcome: LogOutcome
        let minutes: Int
    }

    private var recentLogs: [RecentLog] {
        let titles = Dictionary(items.filter { !$0.isDeleted }.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        let byLog = Dictionary(grouping: entries.filter { !$0.isDeleted }, by: \.blockLogId)
        var out: [RecentLog] = []
        for log in logs where !log.isDeleted && log.areaId == area.id && log.state != .unlogged {
            let es = byLog[log.id] ?? []
            let names = es.compactMap { $0.itemId.flatMap { titles[$0] } }.sorted()
            let minutes = es.isEmpty ? log.loggedMinutes : es.filter { $0.outcome.countsAsWork }.reduce(0) { $0 + $1.minutes }
            out.append(RecentLog(id: log.id, date: log.eventStart, label: names.isEmpty ? "Block" : names.joined(separator: ", "), outcome: LogOutcome(log.state), minutes: minutes))
        }
        for u in unplanned where !u.isDeleted && u.areaId == area.id {
            out.append(RecentLog(id: u.id, date: u.date, label: u.itemId.flatMap { titles[$0] } ?? "Unplanned", outcome: u.outcome, minutes: u.minutes))
        }
        return Array(out.filter { $0.date <= .now }.sorted { $0.date > $1.date }.prefix(10))
    }

    private func complete(_ item: Item) {
        updateItem(store, item, status: .done)
        google.message = UserMessage("Marked done", actionTitle: "Undo") { updateItem(store, item, status: .open) }
    }
}

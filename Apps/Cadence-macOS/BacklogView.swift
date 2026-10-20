import SwiftUI
import SwiftData
import CadenceCore

/// Open tasks and activities by Area. Drag any row onto a block to plan it.
struct BacklogView: View {
    @Environment(AppStore.self) private var store
    @Environment(GoogleService.self) private var google
    @Environment(InsightsModel.self) private var insights

    @Query(sort: \Area.sortOrder) private var areas: [Area]
    @Query private var items: [Item]

    @AppStorage("backlog.collapsed") private var collapsedRaw = ""
    @State private var query = ""
    @State private var editing: Item?

    private var collapsed: Set<String> { Set(collapsedRaw.split(separator: ",").map(String.init)) }
    private var visibleAreas: [Area] { areas.filter { !$0.isDeleted && !$0.isArchived && !$0.isClassesCalendar } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter", text: $query).textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Space.s) {
                    ForEach(visibleAreas) { area in
                        section(area)
                    }
                }
                .padding(Theme.Space.m)
            }
        }
        .sheet(item: $editing) { ItemEditorView(areaId: $0.areaId, item: $0) }
    }

    // MARK: Sections

    private func areaItems(_ area: Area) -> [Item] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let all = items.filter { !$0.isDeleted && $0.areaId == area.id }
        guard !q.isEmpty, !area.name.localizedCaseInsensitiveContains(q) else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    @ViewBuilder
    private func section(_ area: Area) -> some View {
        let all = areaItems(area)
        let tasks = all.filter { $0.kind == .task && $0.status == .open }.sorted(by: Self.taskOrder)
        let activities = all.filter { $0.kind == .activity }.sorted { $0.title < $1.title }
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty

        if !(searching && tasks.isEmpty && activities.isEmpty) {
            DisclosureGroup(isExpanded: expansion(area)) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(tasks) { item in
                        BacklogTaskRow(item: item, areas: visibleAreas, onComplete: { complete(item) }, onEdit: { editing = item },
                                       onMove: { move(item, to: $0) }, onDelete: { delete(item) })
                    }
                    if tasks.isEmpty { Text("No open tasks").font(.callout).foregroundStyle(.tertiary).padding(.vertical, 2) }
                    if !activities.isEmpty {
                        Text("Activities").font(.caption).foregroundStyle(.secondary).padding(.top, Theme.Space.s)
                        ForEach(activities) { item in
                            BacklogActivityRow(item: item, stat: insights.activity(item.id), areas: visibleAreas,
                                               onEdit: { editing = item }, onMove: { move(item, to: $0) }, onDelete: { delete(item) })
                        }
                    }
                    BacklogAddField(area: area)
                }
                .padding(.top, Theme.Space.xs)
            } label: {
                HStack(spacing: Theme.Space.s) {
                    AreaDot(colorHex: area.colorHex)
                    Text(area.name).font(.headline)
                    Spacer()
                    Text("\(tasks.count)").font(.callout).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
    }

    private func expansion(_ area: Area) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(area.id.uuidString) || !query.isEmpty },
            set: { open in
                var set = collapsed
                if open { set.remove(area.id.uuidString) } else { set.insert(area.id.uuidString) }
                collapsedRaw = set.sorted().joined(separator: ",")
            }
        )
    }

    static func taskOrder(_ a: Item, _ b: Item) -> Bool {
        switch (a.dueDate, b.dueDate) {
        case let (x?, y?): return x != y ? x < y : a.createdAt < b.createdAt
        case (nil, nil): return a.createdAt < b.createdAt
        case (nil, _): return false
        case (_, nil): return true
        }
    }

    // MARK: Actions

    private func complete(_ item: Item) {
        updateItem(store, item, status: .done)
        google.message = UserMessage("Marked done", actionTitle: "Undo") { updateItem(store, item, status: .open) }
    }

    private func move(_ item: Item, to area: Area) { updateItem(store, item, areaId: area.id) }

    private func delete(_ item: Item) {
        deleteItem(store, item)
        google.message = UserMessage("Deleted “\(item.title)”", actionTitle: "Undo") {
            item.isDeleted = false
            item.updatedAt = .now
            store.save()
        }
    }
}

// MARK: - Rows

private struct DragPill: View {
    let title: String
    let colorHex: String?
    var body: some View {
        HStack(spacing: 6) {
            if let colorHex { AreaDot(colorHex: colorHex, size: 8) }
            Text(title).font(.callout)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
    }
}

private struct RowMenu: View {
    let item: Item
    let areas: [Area]
    var onEdit: () -> Void
    var onMove: (Area) -> Void
    var onDelete: () -> Void

    var body: some View {
        Menu {
            Button("Edit…", action: onEdit)
            Menu("Move to Area") {
                ForEach(areas.filter { $0.id != item.areaId }) { a in Button(a.name) { onMove(a) } }
            }
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        } label: {
            Image(systemName: "ellipsis").foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct BacklogTaskRow: View {
    let item: Item
    let areas: [Area]
    var onComplete: () -> Void
    var onEdit: () -> Void
    var onMove: (Area) -> Void
    var onDelete: () -> Void

    @State private var hovering = false

    private var overdue: Bool { item.dueDate.map { $0 < Calendar.current.startOfDay(for: .now) } ?? false }

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Button(action: onComplete) { Image(systemName: "circle").foregroundStyle(.secondary) }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark done")
            Text(item.title).font(.callout).lineLimit(2)
            Spacer(minLength: Theme.Space.s)
            if hovering {
                RowMenu(item: item, areas: areas, onEdit: onEdit, onMove: onMove, onDelete: onDelete)
            }
            if let due = item.dueDate {
                if overdue {
                    Text("Overdue").font(.caption).foregroundStyle(.orange.opacity(0.9))
                } else {
                    Text(due, format: .dateTime.month(.abbreviated).day()).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? Color.primary.opacity(0.05) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: onEdit)
        .draggable(item.id.uuidString) { DragPill(title: item.title, colorHex: areas.first { $0.id == item.areaId }?.colorHex) }
    }
}

struct BacklogActivityRow: View {
    let item: Item
    let stat: ActivityStat?
    let areas: [Area]
    var onEdit: () -> Void
    var onMove: (Area) -> Void
    var onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(.tertiary).frame(width: 14)
            Text(item.title).font(.callout).lineLimit(1)
            Spacer(minLength: Theme.Space.s)
            if hovering {
                RowMenu(item: item, areas: areas, onEdit: onEdit, onMove: onMove, onDelete: onDelete)
            }
            if let stat, stat.rawMinutes > 0 {
                Text(stat.level > 0 ? "\(Format.hours(minutes: stat.rawMinutes)) · Level \(stat.level)" : Format.hours(minutes: stat.rawMinutes))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? Color.primary.opacity(0.05) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: onEdit)
        .draggable(item.id.uuidString) { DragPill(title: item.title, colorHex: areas.first { $0.id == item.areaId }?.colorHex) }
    }
}

/// "Add task…" at the end of each Area group. Return adds a task and keeps focus; ⌘Return adds an activity.
struct BacklogAddField: View {
    @Environment(AppStore.self) private var store
    let area: Area

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "plus").font(.caption).foregroundStyle(.tertiary).frame(width: 14)
            TextField("Add task…", text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($focused)
                .onSubmit(add)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .help("Return adds a task, ⌘Return adds an activity")
    }

    private func add() {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let asActivity = NSEvent.modifierFlags.contains(.command)
        createItem(store, kind: asActivity ? .activity : .task, title: title, areaId: area.id)
        text = ""
        focused = true
    }
}

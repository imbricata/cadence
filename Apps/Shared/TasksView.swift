import SwiftUI
import SwiftData
import CadenceCore

enum TaskFilter: String, CaseIterable, Identifiable {
    case open = "Open", due = "Due", completed = "Done"
    var id: String { rawValue }
}

/// One place to act on tasks across every Area, even without Google or AI access.
struct TasksView: View {
    @Environment(AppStore.self) private var store
    @Environment(GoogleService.self) private var google
    @Environment(\.openSettings) private var openSettings
    @Query(sort: \Area.sortOrder) private var areas: [Area]
    @Query private var items: [Item]

    @State private var filter: TaskFilter
    @State private var search = ""
    @State private var selectedArea: UUID?
    @State private var editing: Item?
    @State private var showNew = false
    @State private var showNewArea = false

    init(initialFilter: TaskFilter = .open) {
        #if DEBUG
        if DemoMode.isEnabled, let raw = DemoMode.arg("CadenceTaskFilter"),
           let filter = TaskFilter.allCases.first(where: { $0.rawValue.lowercased() == raw }) {
            _filter = State(initialValue: filter)
            return
        }
        #endif
        _filter = State(initialValue: initialFilter)
    }

    private var activeAreas: [Area] { areas.filter { !$0.isDeleted && !$0.isArchived && !$0.isClassesCalendar } }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let visible = matchingTasks(now: context.date)
            List {
                if filter == .completed {
                    taskSection("Completed", tasks: visible)
                } else {
                    ForEach(TaskBucket.allCases) { bucket in
                        taskSection(bucket.rawValue, tasks: visible.filter {
                            TaskBucket.classify(dueDate: $0.dueDate, now: context.date) == bucket
                        })
                    }
                }
            }
            .overlay {
                if visible.isEmpty { emptyState }
            }
            #if os(macOS)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
            #endif
        }
        .safeAreaInset(edge: .top, spacing: 0) { filters }
        .searchable(text: $search, prompt: "Search tasks or areas")
        .navigationTitle("Tasks")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .statusBanner()
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                Button { openSettings() } label: { Label("Settings", systemImage: "gearshape") }
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if activeAreas.isEmpty { showNewArea = true } else { showNew = true }
                } label: { Label("New Task", systemImage: "plus") }
                .help("Add a task")
            }
        }
        .sheet(isPresented: $showNew) { ItemEditorView(areaId: selectedArea) }
        .sheet(isPresented: $showNewArea) { AreaEditorView(area: nil) }
        .sheet(item: $editing) { ItemEditorView(areaId: $0.areaId, item: $0) }
        .onChange(of: activeAreas.map(\.id)) { _, ids in
            if let selectedArea, !ids.contains(selectedArea) { self.selectedArea = nil }
        }
        #if DEBUG
        .task {
            if DemoMode.isEnabled && DemoMode.arg("CadenceSheet") == "task" { showNew = true }
        }
        #endif
    }

    private var filters: some View {
        VStack(spacing: Theme.Space.s) {
            Picker("Tasks", selection: $filter) {
                ForEach(TaskFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)
            if activeAreas.count > 1 {
                Menu {
                    Button("All Areas") { selectedArea = nil }
                    ForEach(activeAreas) { area in Button(area.name) { selectedArea = area.id } }
                } label: {
                    Label(activeAreas.first { $0.id == selectedArea }?.name ?? "All Areas", systemImage: "line.3.horizontal.decrease")
                        .font(.subheadline)
                }
                .accessibilityLabel("Filter by area")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Space.m)
        .background(.bar)
    }

    @ViewBuilder
    private func taskSection(_ title: String, tasks: [Item]) -> some View {
        if !tasks.isEmpty {
            Section {
                ForEach(tasks) { item in
                    TaskAgendaRow(item: item, area: activeAreas.first { $0.id == item.areaId },
                                  onToggle: { toggle(item) }, onEdit: { editing = item })
                        .contextMenu {
                            Button(item.status == .done ? "Reopen" : "Mark Done") { toggle(item) }
                            Button("Edit…") { editing = item }
                            if item.status == .open {
                                Button("Due Today") { updateItem(store, item, dueDate: Calendar.current.startOfDay(for: .now)) }
                                Button("Due Tomorrow") {
                                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
                                    updateItem(store, item, dueDate: tomorrow)
                                }
                                if item.dueDate != nil {
                                    Button("Remove Due Date") { updateItem(store, item, dueDate: .some(nil)) }
                                }
                            }
                        }
                        #if os(macOS)
                        .draggable(item.id.uuidString)
                        #else
                        .swipeActions(edge: .leading) {
                            Button(item.status == .done ? "Reopen" : "Done", systemImage: "checkmark") { toggle(item) }
                                .tint(.accentColor)
                        }
                        #endif
                }
            } header: {
                HStack {
                    Text(title)
                    Spacer()
                    Text("\(tasks.count)").monospacedDigit()
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: activeAreas.isEmpty ? "square.grid.2x2" : "checklist")
        } description: {
            Text(emptyDescription)
        } actions: {
            if activeAreas.isEmpty { Button("New Area") { showNewArea = true } }
            else if search.isEmpty && filter == .open { Button("New Task") { showNew = true } }
        }
    }

    private var emptyTitle: String {
        if activeAreas.isEmpty { return "Start with an area" }
        if !search.isEmpty { return "No matching tasks" }
        switch filter {
        case .open: return "Nothing open"
        case .due: return "You're up to date"
        case .completed: return "No completed tasks yet"
        }
    }

    private var emptyDescription: String {
        if activeAreas.isEmpty { return "Create an area of your life, then add your first task." }
        if !search.isEmpty { return "Try another search or area." }
        switch filter {
        case .open: return "Capture something you want to get done."
        case .due: return "No overdue tasks or tasks due today in this view."
        case .completed: return "Tasks you finish will appear here."
        }
    }

    private func matchingTasks(now: Date) -> [Item] {
        let areaNames = Dictionary(activeAreas.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates: [Item]
        if filter == .completed {
            candidates = items.filter { !$0.isDeleted && $0.kind == .task && $0.status == .done && areaNames[$0.areaId] != nil }
                .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        } else {
            candidates = TaskAgenda.openTasks(items: items, areas: activeAreas)
        }
        return candidates.filter { item in
            if let selectedArea, item.areaId != selectedArea { return false }
            if filter == .due {
                let bucket = TaskBucket.classify(dueDate: item.dueDate, now: now)
                if bucket != .today && bucket != .overdue { return false }
            }
            return query.isEmpty || item.title.localizedStandardContains(query)
                || (areaNames[item.areaId]?.localizedStandardContains(query) ?? false)
                || (item.notes?.localizedStandardContains(query) ?? false)
        }
    }

    private func toggle(_ item: Item) {
        let previous = item.status
        updateItem(store, item, status: previous == .done ? .open : .done)
        google.message = UserMessage(previous == .done ? "Task reopened" : "Task completed", actionTitle: "Undo") {
            updateItem(store, item, status: previous)
        }
    }
}

private struct TaskAgendaRow: View {
    let item: Item
    let area: Area?
    let onToggle: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Button(action: onToggle) {
                Image(systemName: item.status == .done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.status == .done ? Color.accentColor : .secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.status == .done ? "Reopen" : "Complete") \(item.title)")
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(item.title).foregroundStyle(item.status == .done ? .secondary : .primary)
                        .strikethrough(item.status == .done)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        if let area {
                            AreaDot(colorHex: area.colorHex, size: 7)
                            Text(area.name)
                        }
                        if let due = item.dueDate {
                            Text("·")
                            Text(due, format: .dateTime.month(.abbreviated).day())
                                .monospacedDigit()
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, Theme.Space.xs)
    }
}

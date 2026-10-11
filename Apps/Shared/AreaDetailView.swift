import SwiftUI
import SwiftData
import CadenceCore

struct AreaDetailView: View {
    @Environment(AppStore.self) private var store
    let area: Area

    @Query private var items: [Item]
    @State private var showingItems = false
    @State private var showingEdit = false
    @State private var editingItem: Item?

    private var areaItems: [Item] { items.filter { !$0.isDeleted && $0.areaId == area.id } }
    private var activities: [Item] { areaItems.filter { $0.kind == .activity }.sorted { $0.title < $1.title } }
    private var openTasks: [Item] {
        areaItems.filter { $0.kind == .task && $0.status == .open }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }
    private var doneTasks: [Item] { areaItems.filter { $0.kind == .task && $0.status != .open } }

    var body: some View {
        List {
            if !activities.isEmpty {
                Section("Activities") {
                    ForEach(activities) { item in
                        HStack {
                            Text(item.title)
                            Spacer()
                            Button { selected(item, .activity) } label: { Image(systemName: "pencil") }
                        }
                    }
                }
            }
            if !openTasks.isEmpty {
                Section("Open tasks") {
                    ForEach(openTasks) { item in
                        HStack {
                            Button { markDone(item) } label: {
                                Image(systemName: "circle")
                            }
                            VStack(alignment: .leading) {
                                Text(item.title)
                                if let d = item.dueDate { Text(d, format: .dateTime.day().month()).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Button { selected(item, .task) } label: { Image(systemName: "pencil") }
                        }
                    }
                }
            }
            if !doneTasks.isEmpty {
                Section("Done") {
                    ForEach(doneTasks) { item in
                        Text(item.title).foregroundStyle(.secondary)
                            .swipeActions { Button("Reopen") { reopen(item) } }
                    }
                }
            }
        }
        .navigationTitle(area.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingItems = true } label: { Image(systemName: "plus") }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button { showingEdit = true } label: { Image(systemName: "slider.horizontal.3") }
            }
        }
        .sheet(isPresented: $showingItems) {
            ItemEditorView(areaId: area.id)
        }
        .sheet(isPresented: $showingEdit) {
            AreaEditorView(area: area)
        }
        .sheet(item: $editingItem) { item in
            ItemEditorView(areaId: area.id, item: item)
        }
    }

    private func selected(_ item: Item, _ kind: ItemKind) { editingItem = item }
    private func markDone(_ item: Item) { updateItem(store, item, status: .done) }
    private func reopen(_ item: Item) { updateItem(store, item, status: .open) }
}
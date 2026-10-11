import SwiftUI
import SwiftData
import CadenceCore

struct AreasView: View {
    @Environment(AppStore.self) private var store
    @Environment(GoogleService.self) private var google
    @Query(sort: \Area.sortOrder) private var areas: [Area]
    @Query private var items: [Item]
    @Query private var blockLogs: [BlockLog]
    @Query private var entries: [BlockEntry]
    @State private var showingNew = false

    private var visible: [Area] { areas.filter { !$0.isDeleted && !$0.isArchived } }
    private var classes: [Area] { areas.filter { !$0.isDeleted && $0.isClassesCalendar } }

    private var snapshot: InsightSnapshot {
        _ = (items, blockLogs, entries)
        return computeInsights(context: store.context, events: google.cachedEvents)
    }

    var body: some View {
        NavigationStack {
            List {
                if !classes.isEmpty {
                    Section("Classes") {
                        ForEach(classes) { area in AreaRow(area: area) }
                    }
                }
                Section("Areas") {
                    ForEach(visible) { area in
                        NavigationLink { AreaDetailView(area: area) } label: {
                            AreaRow(area: area, formPercent: form(of: area))
                        }
                    }
                }
            }
            .navigationTitle("Areas")
            .toolbar {
                Button { showingNew = true } label: { Image(systemName: "plus") }
            }
            .sheet(isPresented: $showingNew) {
                AreaEditorView(area: nil)
            }
        }
    }

    private func form(of area: Area) -> Double? {
        snapshot.areas.first { $0.areaId == area.id }?.formPercent
    }
}
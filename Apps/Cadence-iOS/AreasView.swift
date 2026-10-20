import SwiftUI
import SwiftData
import CadenceCore

struct AreasView: View {
    @Environment(AppStore.self) private var store
    @Environment(InsightsModel.self) private var insights
    @Query(sort: \Area.sortOrder) private var areas: [Area]
    @State private var showingNew = false

    private var visible: [Area] { areas.filter { !$0.isDeleted && !$0.isArchived } }
    private var classes: [Area] { areas.filter { !$0.isDeleted && $0.isClassesCalendar } }

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
                    .onMove(perform: move)
                }
            }
            .navigationTitle("Areas")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNew = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingNew) {
                AreaEditorView(area: nil)
            }
        }
    }

    private func form(of area: Area) -> Double? {
        insights.area(area.id)?.formPercent
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = visible
        reordered.move(fromOffsets: source, toOffset: destination)
        reorderAreas(store, reordered)
    }
}
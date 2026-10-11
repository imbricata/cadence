import SwiftUI
import SwiftData
import CadenceCore

struct AreasView: View {
    @Environment(AppStore.self) private var store
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
                        NavigationLink { AreaDetailView(area: area) } label: { AreaRow(area: area) }
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
}
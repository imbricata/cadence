import SwiftUI
import SwiftData
import CadenceCore

struct AreasView: View {
    @Environment(AppStore.self) private var store
    @Environment(InsightsModel.self) private var insights
    @Environment(\.openSettings) private var openSettings
    @Query(sort: \Area.sortOrder) private var areas: [Area]

    @State private var showingNew = false
    @State private var showingClasses = false

    private var visible: [Area] { areas.filter { !$0.isDeleted && !$0.isArchived && !$0.isClassesCalendar } }
    private var classes: Area? { areas.first { !$0.isDeleted && $0.isClassesCalendar } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(visible) { area in
                        NavigationLink { AreaDetailView(area: area) } label: {
                            AreaRow(area: area, formPercent: insights.area(area.id)?.formPercent)
                        }
                        .swipeActions(edge: .trailing) {
                            Button { updateArea(store, area, isArchived: true) } label: { Label("Archive", systemImage: "archivebox") }
                                .tint(.gray)
                        }
                    }
                    .onMove(perform: move)
                } footer: {
                    if visible.isEmpty { EmptyLine(text: "No areas yet. Tap + to add one.") }
                }

                if let classes {
                    Section {
                        Button { showingClasses = true } label: {
                            AreaRow(area: classes, showsForm: false).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    } footer: {
                        Text("Your timetable. Read-only, never scored.")
                    }
                }
            }
            .navigationTitle("Areas")
            .navigationBarTitleDisplayMode(.inline)
            .statusBanner()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { openSettings() } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNew = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New Area")
                }
            }
            .sheet(isPresented: $showingNew) { AreaEditorView(area: nil) }
            #if DEBUG
            .task {
                if DemoMode.arg("CadenceSheet") == "newarea" { try? await Task.sleep(for: .seconds(1.5)); showingNew = true }
            }
            #endif
            .sheet(isPresented: $showingClasses) { ClassesSourceSheet() }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = visible
        reordered.move(fromOffsets: source, toOffset: destination)
        reorderAreas(store, reordered)
    }
}

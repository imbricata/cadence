import SwiftUI
import SwiftData
import CadenceCore

enum SidebarItem: Hashable {
    case plan, inbox, insights
    case area(UUID)
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(GoogleService.self) private var google
    @Environment(InsightsModel.self) private var insights
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \Area.sortOrder) private var areas: [Area]
    @Query private var notes: [InboxNote]

    @State private var selection: SidebarItem? = RootView.initialSelection
    @State private var showNewArea = false
    @State private var showQuickNote = false
    @State private var editingArea: Area?
    @State private var areaToDelete: Area?

    private var visibleAreas: [Area] { areas.filter { !$0.isDeleted && !$0.isArchived && !$0.isClassesCalendar } }
    private var inboxBadge: Int { notes.filter { !$0.isDeleted && $0.state != .sorted }.count }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            detail
                .safeAreaInset(edge: .top, spacing: 0) { StatusBanner() }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in google.setActive(phase == .active) }
        .sheet(isPresented: $showNewArea) { AreaEditorView(area: nil) }
        .sheet(item: $editingArea) { AreaEditorView(area: $0) }
        .sheet(isPresented: $showQuickNote) { QuickNoteSheet() }
        .confirmationDialog(
            "Delete \(areaToDelete?.name ?? "area")?",
            isPresented: Binding(get: { areaToDelete != nil }, set: { if !$0 { areaToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Area", role: .destructive) {
                if let a = areaToDelete { deleteArea(store, a); if selection == .area(a.id) { selection = .plan } }
                areaToDelete = nil
            }
        } message: {
            Text("Its items stay in your data but disappear from the app. The Google calendar is not deleted.")
        }
        .focusedSceneValue(\.rootActions, RootActions(newNote: { showQuickNote = true }))
        .toastHost()
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                Label("Plan", systemImage: "calendar").tag(SidebarItem.plan)
                Label("Inbox", systemImage: "tray")
                    .badge(inboxBadge)
                    .tag(SidebarItem.inbox)
                Label("Insights", systemImage: "chart.bar").tag(SidebarItem.insights)
            }
            Section("Areas") {
                ForEach(visibleAreas) { area in
                    HStack {
                        Label {
                            Text(area.name)
                        } icon: {
                            Image(systemName: area.symbolName).foregroundStyle(area.color.base)
                        }
                        Spacer()
                        if let p = insights.area(area.id)?.formPercent {
                            Text("\(Int(p.rounded()))%").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    .tag(SidebarItem.area(area.id))
                    .contextMenu {
                        Button("Edit…") { editingArea = area }
                        Button("Archive") { archive(area) }
                        Divider()
                        Button("Delete…", role: .destructive) { areaToDelete = area }
                    }
                }
                .onMove { source, destination in
                    var reordered = visibleAreas
                    reordered.move(fromOffsets: source, toOffset: destination)
                    reorderAreas(store, reordered)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button { showNewArea = true } label: {
                Label("New Area", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .plan, .none: PlanView()
        case .inbox: InboxView()
        case .insights: InsightsView()
        case .area(let id):
            if let area = visibleAreas.first(where: { $0.id == id }) {
                AreaDetailView(area: area).id(area.id)
            } else {
                EmptyLine(text: "This area is gone.")
            }
        }
    }

    private func archive(_ area: Area) {
        updateArea(store, area, isArchived: true)
        if selection == .area(area.id) { selection = .plan }
    }

    private static var initialSelection: SidebarItem {
        #if DEBUG
        switch DemoMode.arg("CadenceSection") {
        case "inbox": return .inbox
        case "insights": return .insights
        default: break
        }
        #endif
        return .plan
    }
}

/// ⌘N: type a note, press Return. Doesn't navigate away from whatever you were doing.
struct QuickNoteSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(InboxService.self) private var inbox
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("New note").font(.headline)
            TextField("What's on your mind?", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title3)
                .lineLimit(1...5)
                .focused($focused)
                .onSubmit(send)
            HStack {
                Text("Return to send · Esc to close").font(.caption).foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 460)
        .onAppear { focused = true }
        .onExitCommand { dismiss() }
    }

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        addInboxNote(store, rawText: trimmed)
        Task { await inbox.processPending() }
        dismiss()
    }
}

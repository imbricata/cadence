import SwiftUI
import SwiftData
import CadenceCore

/// Chat-style capture: newest at the bottom, composer under it. Same screen on iPhone and Mac.
struct InboxView: View {
    @Environment(AppStore.self) private var store
    @Environment(InboxService.self) private var inbox
    @Environment(\.openSettings) private var openSettings

    @Query(sort: \InboxNote.createdAt) private var notes: [InboxNote]
    @Query private var items: [Item]
    @Query(sort: \Area.sortOrder) private var areas: [Area]

    @State private var draft = ""
    @State private var editing: Item?
    @FocusState private var focused: Bool

    private var liveNotes: [InboxNote] { notes.filter { !$0.isDeleted } }

    private var groups: [(day: Date, notes: [InboxNote])] {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: liveNotes) { cal.startOfDay(for: $0.createdAt) }
        return byDay.keys.sorted().map { ($0, byDay[$0]!.sorted { $0.createdAt < $1.createdAt }) }
    }

    var body: some View {
        #if os(iOS)
        NavigationStack {
            screen
                .navigationTitle("Inbox")
                .navigationBarTitleDisplayMode(.inline)
                .statusBanner()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { openSettings() } label: { Image(systemName: "gearshape") }
                            .accessibilityLabel("Settings")
                    }
                }
        }
        #else
        screen.navigationTitle("Inbox")
        #endif
    }

    private var screen: some View {
        List {
            ForEach(groups, id: \.day) { group in
                Section {
                    ForEach(group.notes) { note in
                        InboxNoteRow(note: note, item: item(for: note), area: area(for: note), onEdit: { editing = $0 })
                            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(.quaternary.opacity(0.6)))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 3, leading: Theme.Space.l, bottom: 3, trailing: Theme.Space.l))
                            #if os(iOS)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { deleteInboxCard(store, note) } label: { Label("Delete", systemImage: "trash") }
                            }
                            #endif
                    }
                } header: {
                    Text(dayTitle(group.day))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
                .listSectionSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .defaultScrollAnchor(.bottom)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .overlay {
            if liveNotes.isEmpty {
                ContentUnavailableView("Inbox", systemImage: "tray.and.arrow.down", description: Text("Type a quick note below and it becomes an item."))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if !inbox.hasKey { keyHint }
                composer
            }
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
        .onAppear { Task { await inbox.processPending() } }
        #if DEBUG
        .task {
            if DemoMode.arg("CadenceSheet") == "item" {
                try? await Task.sleep(for: .seconds(1.5))
                editing = items.first { !$0.isDeleted && $0.title == "Buy running shoes" }
            }
        }
        #endif
        .sheet(item: $editing) { ItemEditorView(areaId: $0.areaId, item: $0) }
    }

    private var keyHint: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "sparkles").foregroundStyle(.secondary)
            Text("Add an OpenRouter key in Settings to sort notes.").font(.footnote).foregroundStyle(.secondary)
            Spacer()
            #if os(macOS)
            SettingsLink { Text("Settings") }.controlSize(.small)
            #else
            Button("Settings") { openSettings() }.buttonStyle(.bordered).controlSize(.small)
            #endif
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.s)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: Theme.Space.s) {
            TextField("What's on your mind?", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.horizontal, Theme.Space.m + 2)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.quaternary.opacity(0.7)))
                #if os(macOS)
                .onKeyPress(keys: [.return]) { press in
                    if press.modifiers.contains(.shift) { return .ignored }
                    send()
                    return .handled
                }
                #endif
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
            }
            .buttonStyle(.plain)
            .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.4))
            .disabled(!canSend)
            .accessibilityLabel("Send")
            .sensoryFeedback(.success, trigger: notes.count)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s)
    }

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        addInboxNote(store, rawText: text)
        draft = ""
        focused = true
        Task { await inbox.processPending() }
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    private func item(for note: InboxNote) -> Item? {
        guard let id = note.resultingItemId else { return nil }
        return items.first { $0.id == id && !$0.isDeleted }
    }

    private func area(for note: InboxNote) -> Area? {
        guard let item = item(for: note) else { return nil }
        return areas.first { $0.id == item.areaId }
    }
}

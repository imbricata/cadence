import SwiftUI
import SwiftData
import CadenceCore

struct InboxView: View {
    @Environment(AppStore.self) private var store
    @Environment(InboxService.self) private var inbox
    @Query(sort: \InboxNote.createdAt, order: .reverse) private var notes: [InboxNote]
    @Query private var items: [Item]
    @Query(sort: \Area.sortOrder) private var areas: [Area]

    @State private var draft = ""
    @FocusState private var focused: Bool

    private var liveNotes: [InboxNote] { notes.filter { !$0.isDeleted } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(liveNotes) { note in
                    InboxNoteRow(note: note, item: itemFor(note), area: areaFor(note))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
                }
            }
            .padding(12)
        }
        .overlay {
            if liveNotes.isEmpty {
                ContentUnavailableView(
                    "Inbox",
                    systemImage: "tray.and.arrow.down",
                    description: Text("Type a quick note below and it becomes an item.")
                )
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .navigationTitle("Inbox")
        .onAppear { Task { await inbox.processPending() } }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("What's on your mind?", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .focused($focused)
                .lineLimit(1...4)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            Button("Send") { send() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
        .background(.bar)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        addInboxNote(store, rawText: text)
        draft = ""
        Task { await inbox.processPending() }
    }

    private func itemFor(_ note: InboxNote) -> Item? {
        guard let id = note.resultingItemId else { return nil }
        return items.first { $0.id == id }
    }
    private func areaFor(_ note: InboxNote) -> Area? {
        guard let item = itemFor(note) else { return nil }
        return areas.first { $0.id == item.areaId }
    }
}
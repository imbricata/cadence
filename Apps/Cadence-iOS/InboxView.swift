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
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(liveNotes) { note in
                        InboxNoteRow(note: note, item: itemFor(note), area: areaFor(note))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
                    }
                }
                .padding(.vertical, 12)
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
            .navigationTitle("Inbox")
            .safeAreaInset(edge: .bottom) { composer }
            .onAppear { Task { await inbox.processPending() } }
            .defaultFocus($focused, true)
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("What's on your mind?", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .focused($focused)
                .lineLimit(1...4)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
            Button { send() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        addInboxNote(store, rawText: text)
        draft = ""
        focused = true
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
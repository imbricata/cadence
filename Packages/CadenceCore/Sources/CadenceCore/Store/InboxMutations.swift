import Foundation
import SwiftData

@MainActor
@discardableResult
public func addInboxNote(_ store: AppStore, rawText: String) -> InboxNote {
    let note = InboxNote(rawText: rawText.trimmingCharacters(in: .whitespacesAndNewlines))
    store.context.insert(note)
    store.save()
    return note
}

@MainActor
public func deleteInboxNote(_ store: AppStore, _ note: InboxNote) {
    note.isDeleted = true
    note.updatedAt = .now
    store.save()
}

/// Inbox is capture history. Removing a note must not delete a task or a reused activity.
@MainActor
public func deleteInboxCard(_ store: AppStore, _ note: InboxNote) {
    deleteInboxNote(store, note)
}

@MainActor
public func markForResort(_ store: AppStore, _ note: InboxNote) {
    note.state = .pending
    note.failureCount = 0
    note.updatedAt = .now
    store.save()
}

@MainActor
public func completeManually(_ store: AppStore, _ note: InboxNote, itemId: UUID) {
    guard !note.isDeleted else { return }
    note.resultingItemId = itemId
    note.isLowConfidence = false
    note.failureCount = 0
    note.state = .sorted
    note.sortedAt = .now
    note.updatedAt = .now
    store.save()
}

/// Clears raw text on notes successfully sorted more than 30 days ago.
@MainActor
public func purgeOldRawText(_ store: AppStore) {
    let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
    for note in fetchAll(InboxNote.self, in: store.context) where !note.isDeleted && note.state == .sorted {
        if let sortedAt = note.sortedAt, sortedAt < cutoff, !note.rawText.isEmpty {
            note.rawText = ""
            note.updatedAt = .now
        }
    }
    store.save()
}

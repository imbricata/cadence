import Foundation
import SwiftData

// MARK: - Block logs

@MainActor
@discardableResult
public func ensureBlockLog(
    _ store: AppStore, googleEventId: String, eventStart: Date, areaId: UUID, plannedMinutes: Int = 0
) -> BlockLog {
    if let existing = fetchAll(BlockLog.self, in: store.context).first(where: { !$0.isDeleted && $0.googleEventId == googleEventId && $0.eventStart == eventStart }) {
        return existing
    }
    let log = BlockLog(googleEventId: googleEventId, eventStart: eventStart, areaId: areaId, plannedMinutes: plannedMinutes)
    store.context.insert(log)
    store.save()
    return log
}

@MainActor
public func updateBlockLog(
    _ store: AppStore, _ log: BlockLog,
    state: BlockLogState? = nil, loggedMinutes: Int? = nil, plannedMinutes: Int? = nil, note: String?? = nil
) {
    if let state { log.state = state }
    if let loggedMinutes { log.loggedMinutes = loggedMinutes }
    if let plannedMinutes { log.plannedMinutes = plannedMinutes }
    if let note { log.note = note }
    log.updatedAt = .now
    store.save()
}

@MainActor
public func deleteBlockLog(_ store: AppStore, _ log: BlockLog) {
    log.isDeleted = true
    log.updatedAt = .now
    store.save()
}

// MARK: - Block entries

@MainActor
public func upsertEntry(_ store: AppStore, id: UUID? = nil, blockLogId: UUID, itemId: UUID?, outcome: LogOutcome, minutes: Int) {
    if let id, let existing = fetchAll(BlockEntry.self, in: store.context).first(where: { $0.id == id }) {
        existing.blockLogId = blockLogId
        existing.itemId = itemId
        existing.outcome = outcome
        existing.minutes = minutes
        existing.updatedAt = .now
    } else {
        let entry = BlockEntry(id: id ?? UUID(), blockLogId: blockLogId, itemId: itemId, outcome: outcome, minutes: minutes)
        store.context.insert(entry)
    }
    store.save()
}

@MainActor
public func removeEntry(_ store: AppStore, blockLogId: UUID, itemId: UUID?) {
    let matches = fetchAll(BlockEntry.self, in: store.context)
        .filter { !$0.isDeleted && $0.blockLogId == blockLogId && $0.itemId == itemId }
    for e in matches {
        e.isDeleted = true
        e.updatedAt = .now
    }
    store.save()
}

// MARK: - Unplanned

@MainActor
public func addUnplannedLog(_ store: AppStore, areaId: UUID, itemId: UUID? = nil, date: Date = .now, outcome: LogOutcome, minutes: Int, note: String? = nil) {
    let log = UnplannedLog(areaId: areaId, itemId: itemId, date: date, outcome: outcome, minutes: minutes, note: note)
    store.context.insert(log)
    store.save()
}

// MARK: - Targets

@MainActor
public func upsertTarget(_ store: AppStore, areaId: UUID, weeklyMinutes: Int?, weeklySessions: Int?) {
    if let existing = fetchAll(Target.self, in: store.context).first(where: { !$0.isDeleted && $0.areaId == areaId }) {
        existing.weeklyMinutes = weeklyMinutes
        existing.weeklySessions = weeklySessions
        existing.setAt = .now
        existing.updatedAt = .now
    } else {
        let t = Target(areaId: areaId, weeklyMinutes: weeklyMinutes, weeklySessions: weeklySessions)
        store.context.insert(t)
    }
    store.save()
}

// MARK: - Task completion rules

/// Full -> done (and completedAt). Easy / Skipped -> stay open.
@MainActor
public func applyOutcomeToTask(_ store: AppStore, itemId: UUID, outcome: LogOutcome) {
    guard let item = fetchAll(Item.self, in: store.context).first(where: { $0.id == itemId && !$0.isDeleted }) else { return }
    guard item.kind == .task else { return }
    if outcome == .full {
        if item.status != .done {
            item.status = .done
            item.completedAt = .now
            item.updatedAt = .now
        }
    } else {
        if item.status == .done {
            item.status = .open
            item.completedAt = nil
            item.updatedAt = .now
        }
    }
    store.save()
}

/// Adds an item to a block (default Full, share of block time). Used by drag-to-fill.
@MainActor
public func addItemToBlock(_ store: AppStore, item: Item, googleEventId: String, eventStart: Date, areaId: UUID, plannedMinutes: Int) {
    let log = ensureBlockLog(store, googleEventId: googleEventId, eventStart: eventStart, areaId: areaId, plannedMinutes: plannedMinutes)
    let existing = blockEntries(forLogId: log.id, in: store.context).count
    let share = max(5, plannedMinutes / (existing + 1))
    upsertEntry(store, blockLogId: log.id, itemId: item.id, outcome: .full, minutes: share)
}
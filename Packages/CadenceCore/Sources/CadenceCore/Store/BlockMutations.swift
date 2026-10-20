import Foundation
import SwiftData

// MARK: - Block reference

/// Identifies one block instance (Google event + instance start) plus what's needed to create its log lazily.
public struct BlockRef: Sendable, Hashable {
    public var googleEventId: String
    public var eventStart: Date
    public var areaId: UUID
    public var plannedMinutes: Int

    public init(googleEventId: String, eventStart: Date, areaId: UUID, plannedMinutes: Int) {
        self.googleEventId = googleEventId
        self.eventStart = eventStart
        self.areaId = areaId
        self.plannedMinutes = max(1, plannedMinutes)
    }

    public init(event: CalendarEvent, areaId: UUID) {
        self.init(
            googleEventId: event.id, eventStart: event.start, areaId: areaId,
            plannedMinutes: Int(event.end.timeIntervalSince(event.start) / 60)
        )
    }
}

// MARK: - Block logs

/// Finds the log for a block **without creating one**. Opening a block must never write anything.
@MainActor
public func findBlockLog(_ store: AppStore, googleEventId: String, eventStart: Date) -> BlockLog? {
    fetchAll(BlockLog.self, in: store.context)
        .first { !$0.isDeleted && $0.googleEventId == googleEventId && $0.eventStart == eventStart }
}

@MainActor
@discardableResult
public func ensureBlockLog(_ store: AppStore, _ ref: BlockRef) -> BlockLog {
    if let existing = findBlockLog(store, googleEventId: ref.googleEventId, eventStart: ref.eventStart) {
        return existing
    }
    let log = BlockLog(googleEventId: ref.googleEventId, eventStart: ref.eventStart, areaId: ref.areaId, plannedMinutes: ref.plannedMinutes)
    store.context.insert(log)
    store.save()
    return log
}

@MainActor
public func deleteBlockLog(_ store: AppStore, _ log: BlockLog) {
    for e in blockEntries(forLogId: log.id, in: store.context) {
        e.isDeleted = true
        e.updatedAt = .now
    }
    log.isDeleted = true
    log.updatedAt = .now
    store.save()
}

/// Called after a block is moved or resized so its log follows the event.
@MainActor
public func rekeyBlockLog(_ store: AppStore, googleEventId: String, oldStart: Date, newStart: Date, plannedMinutes: Int) {
    guard let log = findBlockLog(store, googleEventId: googleEventId, eventStart: oldStart) else { return }
    log.eventStart = newStart
    log.plannedMinutes = max(1, plannedMinutes)
    log.updatedAt = .now
    store.save()
}

// MARK: - Planning (never changes scores or tasks)

/// Adds an item to a block as a *plan*. If the block is already logged, the new entry takes the block's outcome.
@MainActor
@discardableResult
public func planItem(_ store: AppStore, item: Item, in ref: BlockRef) -> BlockEntry {
    let log = ensureBlockLog(store, ref)
    if let existing = blockEntries(forLogId: log.id, in: store.context).first(where: { $0.itemId == item.id }) {
        return existing
    }
    let entry = BlockEntry(blockLogId: log.id, itemId: item.id, outcome: .planned, minutes: 0)
    store.context.insert(entry)
    if log.state != .unlogged {
        entry.outcome = LogOutcome(log.state)
        redistributeMinutes(store, log)
        applyOutcomeToTask(store, itemId: item.id, outcome: entry.outcome)
    }
    store.save()
    return entry
}

/// Removes an item from a block. If it had been logged Full, its task reopens.
@MainActor
public func unplanItem(_ store: AppStore, itemId: UUID, in ref: BlockRef) {
    guard let log = findBlockLog(store, googleEventId: ref.googleEventId, eventStart: ref.eventStart) else { return }
    for e in blockEntries(forLogId: log.id, in: store.context) where e.itemId == itemId {
        let wasFull = e.outcome == .full
        e.isDeleted = true
        e.updatedAt = .now
        if wasFull { applyOutcomeToTask(store, itemId: itemId, outcome: .planned) }
    }
    if log.state != .unlogged { redistributeMinutes(store, log) }
    store.save()
}

/// Drag-to-fill from the backlog.
@MainActor
public func addItemToBlock(_ store: AppStore, item: Item, googleEventId: String, eventStart: Date, areaId: UUID, plannedMinutes: Int) {
    planItem(store, item: item, in: BlockRef(googleEventId: googleEventId, eventStart: eventStart, areaId: areaId, plannedMinutes: plannedMinutes))
}

// MARK: - Logging (explicit)

/// Logs the whole block. Every item in it takes the same outcome with default minutes; override per item afterwards.
/// Passing `.unlogged` is the same as `clearBlockLog`.
@MainActor
public func logBlock(_ store: AppStore, _ ref: BlockRef, state: BlockLogState) {
    guard state != .unlogged else {
        if let log = findBlockLog(store, googleEventId: ref.googleEventId, eventStart: ref.eventStart) {
            clearBlockLog(store, log)
        }
        return
    }
    let log = ensureBlockLog(store, ref)
    log.plannedMinutes = ref.plannedMinutes
    log.state = state
    let outcome = LogOutcome(state)
    let entries = blockEntries(forLogId: log.id, in: store.context)
    for e in entries {
        e.outcome = outcome
        e.updatedAt = .now
    }
    log.loggedMinutes = defaultBlockMinutes(state: state, plannedMinutes: log.plannedMinutes)
    redistributeMinutes(store, log)
    for e in entries {
        if let id = e.itemId { applyOutcomeToTask(store, itemId: id, outcome: outcome) }
    }
    log.updatedAt = .now
    store.save()
}

/// Back to "planned, not logged". Items stay in the block; tasks this block had completed reopen.
@MainActor
public func clearBlockLog(_ store: AppStore, _ log: BlockLog) {
    log.state = .unlogged
    log.loggedMinutes = 0
    log.updatedAt = .now
    for e in blockEntries(forLogId: log.id, in: store.context) {
        let wasFull = e.outcome == .full
        e.outcome = .planned
        e.minutes = 0
        e.updatedAt = .now
        if wasFull, let id = e.itemId { applyOutcomeToTask(store, itemId: id, outcome: .planned) }
    }
    store.save()
}

/// Per-item override inside a logged block.
@MainActor
public func setEntryOutcome(_ store: AppStore, _ entry: BlockEntry, outcome: LogOutcome, blockMinutes: Int) {
    let log = fetchAll(BlockLog.self, in: store.context).first { $0.id == entry.blockLogId }
    let count = log.map { blockEntries(forLogId: $0.id, in: store.context).count } ?? 1
    entry.outcome = outcome
    entry.minutes = defaultEntryMinutes(outcome: outcome, blockMinutes: blockMinutes, itemCount: count)
    entry.updatedAt = .now
    if let id = entry.itemId { applyOutcomeToTask(store, itemId: id, outcome: outcome) }
    if let log { syncLoggedMinutes(log, store) }
    store.save()
}

@MainActor
public func setEntryMinutes(_ store: AppStore, _ entry: BlockEntry, minutes: Int) {
    entry.minutes = max(0, minutes)
    entry.updatedAt = .now
    if let log = fetchAll(BlockLog.self, in: store.context).first(where: { $0.id == entry.blockLogId }) {
        syncLoggedMinutes(log, store)
    }
    store.save()
}

/// Minutes for a block with no item entries.
@MainActor
public func setBlockMinutes(_ store: AppStore, _ log: BlockLog, minutes: Int) {
    log.loggedMinutes = max(0, minutes)
    log.updatedAt = .now
    store.save()
}

@MainActor
public func setBlockNote(_ store: AppStore, _ log: BlockLog, note: String?) {
    let clean = note?.trimmingCharacters(in: .whitespacesAndNewlines)
    log.note = (clean?.isEmpty ?? true) ? nil : clean
    log.updatedAt = .now
    store.save()
}

/// Re-split default minutes across entries after the item set changed.
@MainActor
private func redistributeMinutes(_ store: AppStore, _ log: BlockLog) {
    let entries = blockEntries(forLogId: log.id, in: store.context)
    guard !entries.isEmpty else { return }
    for e in entries {
        e.minutes = defaultEntryMinutes(outcome: e.outcome, blockMinutes: log.plannedMinutes, itemCount: entries.count)
        e.updatedAt = .now
    }
    syncLoggedMinutes(log, store)
}

@MainActor
private func syncLoggedMinutes(_ log: BlockLog, _ store: AppStore) {
    let entries = blockEntries(forLogId: log.id, in: store.context)
    guard !entries.isEmpty else { return }
    log.loggedMinutes = entries.reduce(0) { $0 + $1.minutes }
    log.updatedAt = .now
}

// MARK: - Entry upsert / removal (low-level)

@MainActor
public func removeEntry(_ store: AppStore, blockLogId: UUID, itemId: UUID?) {
    let matches = blockEntries(forLogId: blockLogId, in: store.context).filter { $0.itemId == itemId }
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

/// Logged Full -> done (with completedAt). Anything else (easy, skipped, planned/cleared) -> stays open, and
/// reopens a task that was done.
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
    } else if item.status == .done {
        item.status = .open
        item.completedAt = nil
        item.updatedAt = .now
    }
    store.save()
}

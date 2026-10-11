import Foundation
import SwiftData

// MARK: - Sync record protocol

public protocol SyncRecord: Codable, Sendable {
    var id: UUID { get }
    var updatedAt: Date { get }
    var isDeleted: Bool { get }
}

// MARK: - Snapshots

public struct AreaSnapshot: SyncRecord {
    public var id: UUID
    public var updatedAt: Date
    public var isDeleted: Bool
    public var name: String
    public var colorHex: String
    public var symbolName: String
    public var sortOrder: Int
    public var googleCalendarId: String
    public var isClassesCalendar: Bool
    public var isArchived: Bool
    public var createdAt: Date

    public init(_ m: Area) {
        id = m.id; updatedAt = m.updatedAt; isDeleted = m.isDeleted
        name = m.name; colorHex = m.colorHex; symbolName = m.symbolName; sortOrder = m.sortOrder
        googleCalendarId = m.googleCalendarId; isClassesCalendar = m.isClassesCalendar
        isArchived = m.isArchived; createdAt = m.createdAt
    }
}

public struct ItemSnapshot: SyncRecord {
    public var id: UUID
    public var updatedAt: Date
    public var isDeleted: Bool
    public var kind: ItemKind
    public var title: String
    public var areaId: UUID
    public var fullVersion: String?
    public var easyVersion: String?
    public var dueDate: Date?
    public var status: ItemStatus
    public var notes: String?
    public var createdAt: Date
    public var completedAt: Date?

    public init(_ m: Item) {
        id = m.id; updatedAt = m.updatedAt; isDeleted = m.isDeleted
        kind = m.kind; title = m.title; areaId = m.areaId; fullVersion = m.fullVersion
        easyVersion = m.easyVersion; dueDate = m.dueDate; status = m.status
        notes = m.notes; createdAt = m.createdAt; completedAt = m.completedAt
    }
}

public struct InboxNoteSnapshot: SyncRecord {
    public var id: UUID
    public var updatedAt: Date
    public var isDeleted: Bool
    public var rawText: String
    public var createdAt: Date
    public var state: InboxNoteState
    public var resultingItemId: UUID?
    public var sortedAt: Date?
    public var failureCount: Int

    public init(_ m: InboxNote) {
        id = m.id; updatedAt = m.updatedAt; isDeleted = m.isDeleted
        rawText = m.rawText; createdAt = m.createdAt; state = m.state
        resultingItemId = m.resultingItemId; sortedAt = m.sortedAt; failureCount = m.failureCount
    }
}

public struct BlockLogSnapshot: SyncRecord {
    public var id: UUID
    public var updatedAt: Date
    public var isDeleted: Bool
    public var googleEventId: String
    public var eventStart: Date
    public var areaId: UUID
    public var plannedMinutes: Int
    public var state: BlockLogState
    public var loggedMinutes: Int
    public var note: String?

    public init(_ m: BlockLog) {
        id = m.id; updatedAt = m.updatedAt; isDeleted = m.isDeleted
        googleEventId = m.googleEventId; eventStart = m.eventStart; areaId = m.areaId
        plannedMinutes = m.plannedMinutes; state = m.state; loggedMinutes = m.loggedMinutes; note = m.note
    }
}

public struct BlockEntrySnapshot: SyncRecord {
    public var id: UUID
    public var updatedAt: Date
    public var isDeleted: Bool
    public var blockLogId: UUID
    public var itemId: UUID?
    public var outcome: LogOutcome
    public var minutes: Int

    public init(_ m: BlockEntry) {
        id = m.id; updatedAt = m.updatedAt; isDeleted = m.isDeleted
        blockLogId = m.blockLogId; itemId = m.itemId; outcome = m.outcome; minutes = m.minutes
    }
}

public struct UnplannedLogSnapshot: SyncRecord {
    public var id: UUID
    public var updatedAt: Date
    public var isDeleted: Bool
    public var areaId: UUID
    public var itemId: UUID?
    public var date: Date
    public var outcome: LogOutcome
    public var minutes: Int
    public var note: String?

    public init(_ m: UnplannedLog) {
        id = m.id; updatedAt = m.updatedAt; isDeleted = m.isDeleted
        areaId = m.areaId; itemId = m.itemId; date = m.date; outcome = m.outcome
        minutes = m.minutes; note = m.note
    }
}

public struct TargetSnapshot: SyncRecord {
    public var id: UUID
    public var updatedAt: Date
    public var isDeleted: Bool
    public var areaId: UUID
    public var weeklyMinutes: Int?
    public var weeklySessions: Int?
    public var setAt: Date

    public init(_ m: Target) {
        id = m.id; updatedAt = m.updatedAt; isDeleted = m.isDeleted
        areaId = m.areaId; weeklyMinutes = m.weeklyMinutes; weeklySessions = m.weeklySessions; setAt = m.setAt
    }
}

// MARK: - Engine

public struct SyncSummary: Sendable {
    public var lastSyncAt: Date = .now
    public var uploaded: Int = 0
    public var applied: Int = 0
}

@MainActor
public final class SyncEngine {
    static let purgeInterval: TimeInterval = 90 * 24 * 3600

    private let drive = DriveAPI()

    public init() {}

    public func syncAll(auth: GoogleAuth, store: AppStore) async throws -> SyncSummary {
        let token = try await auth.accessToken()
        let files = try await drive.listFiles(accessToken: token)
        let context = store.context

        var summary = SyncSummary()

        // Each block downloads remote, merges with local, applies winners, uploads the result.
        try await syncType(AreaSnapshot.self, name: "cadence-areas.json", token: token, files: files,
                           local: fetchAll(Area.self, in: context).map(AreaSnapshot.init),
                           apply: Self.applyArea, context: context, summary: &summary)
        try await syncType(ItemSnapshot.self, name: "cadence-items.json", token: token, files: files,
                           local: fetchAll(Item.self, in: context).map(ItemSnapshot.init),
                           apply: Self.applyItem, context: context, summary: &summary)
        try await syncType(InboxNoteSnapshot.self, name: "cadence-inbox.json", token: token, files: files,
                           local: fetchAll(InboxNote.self, in: context).map(InboxNoteSnapshot.init),
                           apply: Self.applyInbox, context: context, summary: &summary)
        try await syncType(BlockLogSnapshot.self, name: "cadence-blocklogs.json", token: token, files: files,
                           local: fetchAll(BlockLog.self, in: context).map(BlockLogSnapshot.init),
                           apply: Self.applyBlockLog, context: context, summary: &summary)
        try await syncType(BlockEntrySnapshot.self, name: "cadence-blockentries.json", token: token, files: files,
                           local: fetchAll(BlockEntry.self, in: context).map(BlockEntrySnapshot.init),
                           apply: Self.applyBlockEntry, context: context, summary: &summary)
        try await syncType(UnplannedLogSnapshot.self, name: "cadence-unplanned.json", token: token, files: files,
                           local: fetchAll(UnplannedLog.self, in: context).map(UnplannedLogSnapshot.init),
                           apply: Self.applyUnplanned, context: context, summary: &summary)
        try await syncType(TargetSnapshot.self, name: "cadence-targets.json", token: token, files: files,
                           local: fetchAll(Target.self, in: context).map(TargetSnapshot.init),
                           apply: Self.applyTarget, context: context, summary: &summary)

        store.save()
        return summary
    }

    @MainActor
    private func syncType<T: SyncRecord>(
        _ type: T.Type, name: String, token: String, files: [String: String],
        local: [T], apply: (T, ModelContext) -> Void,
        context: ModelContext, summary: inout SyncSummary
    ) async throws {
        var remote: [T] = []
        if let fileId = files[name] {
            let data = try await drive.downloadFile(accessToken: token, fileId: fileId)
            remote = (try? JSONDecoder().decode([T].self, from: data)) ?? []
        }

        var applied = 0
        let merged = Self.merge(remote: remote, local: local) { snapshot in
            apply(snapshot, context)
            applied += 1
        }
        summary.applied += applied

        let sorted = merged.sorted { $0.id.uuidString < $1.id.uuidString }
        let data = try JSONEncoder().encode(sorted)
        let remoteSorted = remote.sorted { $0.id.uuidString < $1.id.uuidString }
        let remoteData = try JSONEncoder().encode(remoteSorted)

        if let fileId = files[name] {
            if data != remoteData {
                try await drive.updateFile(accessToken: token, fileId: fileId, data: data)
                summary.uploaded += 1
            }
        } else {
            _ = try await drive.createFile(accessToken: token, name: name, data: data)
            summary.uploaded += 1
        }
    }

    /// Newest updatedAt wins. Returns the merged record set (tombstones older than the purge
    /// interval are dropped).
    static func merge<T: SyncRecord>(remote: [T], local: [T], apply: (T) -> Void) -> [T] {
        var merged: [UUID: T] = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        let localIds = Set(local.map(\.id))
        let cutoff = Date().addingTimeInterval(-purgeInterval)

        for localRecord in local {
            if let remoteRecord = merged[localRecord.id] {
                if remoteRecord.updatedAt > localRecord.updatedAt {
                    apply(remoteRecord)
                } else {
                    merged[localRecord.id] = localRecord
                }
            } else {
                merged[localRecord.id] = localRecord
            }
        }
        for (id, remoteRecord) in merged where !localIds.contains(id) {
            apply(remoteRecord)
        }
        return merged.values.filter { !($0.isDeleted && $0.updatedAt < cutoff) }
    }

    // MARK: - Apply helpers

    static func applyArea(_ s: AreaSnapshot, _ context: ModelContext) {
        if let ex = findArea(s.id, context) {
            if s.isDeleted { ex.isDeleted = true; ex.updatedAt = s.updatedAt; return }
            ex.updatedAt = s.updatedAt; ex.isDeleted = false
            ex.name = s.name; ex.colorHex = s.colorHex; ex.symbolName = s.symbolName
            ex.sortOrder = s.sortOrder; ex.googleCalendarId = s.googleCalendarId
            ex.isClassesCalendar = s.isClassesCalendar; ex.isArchived = s.isArchived
        } else if !s.isDeleted {
            context.insert(Area(id: s.id, updatedAt: s.updatedAt, name: s.name, colorHex: s.colorHex,
                                symbolName: s.symbolName, sortOrder: s.sortOrder,
                                googleCalendarId: s.googleCalendarId, isClassesCalendar: s.isClassesCalendar,
                                isArchived: s.isArchived, createdAt: s.createdAt))
        }
    }

    static func applyItem(_ s: ItemSnapshot, _ context: ModelContext) {
        if let ex = findItem(s.id, context) {
            if s.isDeleted { ex.isDeleted = true; ex.updatedAt = s.updatedAt; return }
            ex.updatedAt = s.updatedAt; ex.isDeleted = false
            ex.kind = s.kind; ex.title = s.title; ex.areaId = s.areaId
            ex.fullVersion = s.fullVersion; ex.easyVersion = s.easyVersion; ex.dueDate = s.dueDate
            ex.status = s.status; ex.notes = s.notes; ex.completedAt = s.completedAt
        } else if !s.isDeleted {
            context.insert(Item(id: s.id, updatedAt: s.updatedAt, kind: s.kind, title: s.title, areaId: s.areaId,
                                fullVersion: s.fullVersion, easyVersion: s.easyVersion, dueDate: s.dueDate,
                                status: s.status, notes: s.notes, createdAt: s.createdAt, completedAt: s.completedAt))
        }
    }

    static func applyInbox(_ s: InboxNoteSnapshot, _ context: ModelContext) {
        if let ex = findInbox(s.id, context) {
            if s.isDeleted { ex.isDeleted = true; ex.updatedAt = s.updatedAt; return }
            ex.updatedAt = s.updatedAt; ex.isDeleted = false
            ex.rawText = s.rawText; ex.state = s.state; ex.resultingItemId = s.resultingItemId
            ex.sortedAt = s.sortedAt; ex.failureCount = s.failureCount
        } else if !s.isDeleted {
            context.insert(InboxNote(id: s.id, updatedAt: s.updatedAt, rawText: s.rawText, createdAt: s.createdAt,
                                     state: s.state, resultingItemId: s.resultingItemId, sortedAt: s.sortedAt,
                                     failureCount: s.failureCount))
        }
    }

    static func applyBlockLog(_ s: BlockLogSnapshot, _ context: ModelContext) {
        if let ex = findBlockLog(s.id, context) {
            if s.isDeleted { ex.isDeleted = true; ex.updatedAt = s.updatedAt; return }
            ex.updatedAt = s.updatedAt; ex.isDeleted = false
            ex.googleEventId = s.googleEventId; ex.eventStart = s.eventStart; ex.areaId = s.areaId
            ex.plannedMinutes = s.plannedMinutes; ex.state = s.state; ex.loggedMinutes = s.loggedMinutes; ex.note = s.note
        } else if !s.isDeleted {
            context.insert(BlockLog(id: s.id, updatedAt: s.updatedAt, googleEventId: s.googleEventId,
                                    eventStart: s.eventStart, areaId: s.areaId, plannedMinutes: s.plannedMinutes,
                                    state: s.state, loggedMinutes: s.loggedMinutes, note: s.note))
        }
    }

    static func applyBlockEntry(_ s: BlockEntrySnapshot, _ context: ModelContext) {
        if let ex = findBlockEntry(s.id, context) {
            if s.isDeleted { ex.isDeleted = true; ex.updatedAt = s.updatedAt; return }
            ex.updatedAt = s.updatedAt; ex.isDeleted = false
            ex.blockLogId = s.blockLogId; ex.itemId = s.itemId; ex.outcome = s.outcome; ex.minutes = s.minutes
        } else if !s.isDeleted {
            context.insert(BlockEntry(id: s.id, updatedAt: s.updatedAt, blockLogId: s.blockLogId,
                                      itemId: s.itemId, outcome: s.outcome, minutes: s.minutes))
        }
    }

    static func applyUnplanned(_ s: UnplannedLogSnapshot, _ context: ModelContext) {
        if let ex = findUnplanned(s.id, context) {
            if s.isDeleted { ex.isDeleted = true; ex.updatedAt = s.updatedAt; return }
            ex.updatedAt = s.updatedAt; ex.isDeleted = false
            ex.areaId = s.areaId; ex.itemId = s.itemId; ex.date = s.date; ex.outcome = s.outcome
            ex.minutes = s.minutes; ex.note = s.note
        } else if !s.isDeleted {
            context.insert(UnplannedLog(id: s.id, updatedAt: s.updatedAt, areaId: s.areaId, itemId: s.itemId,
                                        date: s.date, outcome: s.outcome, minutes: s.minutes, note: s.note))
        }
    }

    static func applyTarget(_ s: TargetSnapshot, _ context: ModelContext) {
        if let ex = findTarget(s.id, context) ?? findTargetByArea(s.areaId, context) {
            if s.isDeleted { ex.isDeleted = true; ex.updatedAt = s.updatedAt; return }
            ex.updatedAt = s.updatedAt; ex.isDeleted = false; ex.id = s.id
            ex.weeklyMinutes = s.weeklyMinutes; ex.weeklySessions = s.weeklySessions; ex.setAt = s.setAt
        } else if !s.isDeleted {
            context.insert(Target(id: s.id, updatedAt: s.updatedAt, areaId: s.areaId,
                                  weeklyMinutes: s.weeklyMinutes, weeklySessions: s.weeklySessions, setAt: s.setAt))
        }
    }

    // MARK: - Lookups

    private static func findArea(_ id: UUID, _ c: ModelContext) -> Area? { fetchAll(Area.self, in: c).first { $0.id == id } }
    private static func findItem(_ id: UUID, _ c: ModelContext) -> Item? { fetchAll(Item.self, in: c).first { $0.id == id } }
    private static func findInbox(_ id: UUID, _ c: ModelContext) -> InboxNote? { fetchAll(InboxNote.self, in: c).first { $0.id == id } }
    private static func findBlockLog(_ id: UUID, _ c: ModelContext) -> BlockLog? { fetchAll(BlockLog.self, in: c).first { $0.id == id } }
    private static func findBlockEntry(_ id: UUID, _ c: ModelContext) -> BlockEntry? { fetchAll(BlockEntry.self, in: c).first { $0.id == id } }
    private static func findUnplanned(_ id: UUID, _ c: ModelContext) -> UnplannedLog? { fetchAll(UnplannedLog.self, in: c).first { $0.id == id } }
    private static func findTarget(_ id: UUID, _ c: ModelContext) -> Target? { fetchAll(Target.self, in: c).first { $0.id == id } }
    private static func findTargetByArea(_ areaId: UUID, _ c: ModelContext) -> Target? { fetchAll(Target.self, in: c).first { !$0.isDeleted && $0.areaId == areaId } }
}
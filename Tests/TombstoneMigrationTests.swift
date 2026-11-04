import Foundation
import SwiftData
import XCTest
import CadenceCore

private enum LegacyTombstoneSchema {
    static let models: [any PersistentModel.Type] = [
        Area.self, Item.self, InboxNote.self, BlockLog.self, BlockEntry.self, UnplannedLog.self, Target.self
    ]

    static var schema: Schema { Schema(models) }

    @Model
    final class Area {
        var id: UUID
        var updatedAt: Date
        var isDeleted: Bool
        var name: String
        var colorHex: String
        var symbolName: String
        var sortOrder: Int
        var googleCalendarId: String
        var isClassesCalendar: Bool
        var isArchived: Bool
        var createdAt: Date

        init(
            id: UUID = UUID(),
            updatedAt: Date = .now,
            isDeleted: Bool = false,
            name: String,
            colorHex: String,
            symbolName: String,
            sortOrder: Int = 0,
            googleCalendarId: String = "",
            isClassesCalendar: Bool = false,
            isArchived: Bool = false,
            createdAt: Date = .now
        ) {
            self.id = id
            self.updatedAt = updatedAt
            self.isDeleted = isDeleted
            self.name = name
            self.colorHex = colorHex
            self.symbolName = symbolName
            self.sortOrder = sortOrder
            self.googleCalendarId = googleCalendarId
            self.isClassesCalendar = isClassesCalendar
            self.isArchived = isArchived
            self.createdAt = createdAt
        }
    }

    @Model
    final class Item {
        var id: UUID
        var updatedAt: Date
        var isDeleted: Bool
        var kind: ItemKind
        var title: String
        var areaId: UUID
        var fullVersion: String?
        var easyVersion: String?
        var dueDate: Date?
        var status: ItemStatus
        var notes: String?
        var createdAt: Date
        var completedAt: Date?

        init(
            id: UUID = UUID(),
            updatedAt: Date = .now,
            isDeleted: Bool = false,
            kind: ItemKind,
            title: String,
            areaId: UUID,
            fullVersion: String? = nil,
            easyVersion: String? = nil,
            dueDate: Date? = nil,
            status: ItemStatus = .open,
            notes: String? = nil,
            createdAt: Date = .now,
            completedAt: Date? = nil
        ) {
            self.id = id
            self.updatedAt = updatedAt
            self.isDeleted = isDeleted
            self.kind = kind
            self.title = title
            self.areaId = areaId
            self.fullVersion = fullVersion
            self.easyVersion = easyVersion
            self.dueDate = dueDate
            self.status = status
            self.notes = notes
            self.createdAt = createdAt
            self.completedAt = completedAt
        }
    }

    @Model
    final class InboxNote {
        var id: UUID
        var updatedAt: Date
        var isDeleted: Bool
        var rawText: String
        var createdAt: Date
        var state: InboxNoteState
        var resultingItemId: UUID?
        var sortedAt: Date?
        var failureCount: Int
        var isLowConfidence: Bool = false

        init(
            id: UUID = UUID(),
            updatedAt: Date = .now,
            isDeleted: Bool = false,
            rawText: String,
            createdAt: Date = .now,
            state: InboxNoteState = .pending,
            resultingItemId: UUID? = nil,
            sortedAt: Date? = nil,
            failureCount: Int = 0,
            isLowConfidence: Bool = false
        ) {
            self.id = id
            self.updatedAt = updatedAt
            self.isDeleted = isDeleted
            self.rawText = rawText
            self.createdAt = createdAt
            self.state = state
            self.resultingItemId = resultingItemId
            self.sortedAt = sortedAt
            self.failureCount = failureCount
            self.isLowConfidence = isLowConfidence
        }
    }

    @Model
    final class BlockLog {
        var id: UUID
        var updatedAt: Date
        var isDeleted: Bool
        var googleEventId: String
        var eventStart: Date
        var areaId: UUID
        var plannedMinutes: Int
        var state: BlockLogState
        var loggedMinutes: Int
        var note: String?

        init(
            id: UUID = UUID(),
            updatedAt: Date = .now,
            isDeleted: Bool = false,
            googleEventId: String,
            eventStart: Date,
            areaId: UUID,
            plannedMinutes: Int = 0,
            state: BlockLogState = .unlogged,
            loggedMinutes: Int = 0,
            note: String? = nil
        ) {
            self.id = id
            self.updatedAt = updatedAt
            self.isDeleted = isDeleted
            self.googleEventId = googleEventId
            self.eventStart = eventStart
            self.areaId = areaId
            self.plannedMinutes = plannedMinutes
            self.state = state
            self.loggedMinutes = loggedMinutes
            self.note = note
        }
    }

    @Model
    final class BlockEntry {
        var id: UUID
        var updatedAt: Date
        var isDeleted: Bool
        var blockLogId: UUID
        var itemId: UUID?
        var outcome: LogOutcome
        var minutes: Int

        init(
            id: UUID = UUID(),
            updatedAt: Date = .now,
            isDeleted: Bool = false,
            blockLogId: UUID,
            itemId: UUID? = nil,
            outcome: LogOutcome,
            minutes: Int = 0
        ) {
            self.id = id
            self.updatedAt = updatedAt
            self.isDeleted = isDeleted
            self.blockLogId = blockLogId
            self.itemId = itemId
            self.outcome = outcome
            self.minutes = minutes
        }
    }

    @Model
    final class UnplannedLog {
        var id: UUID
        var updatedAt: Date
        var isDeleted: Bool
        var areaId: UUID
        var itemId: UUID?
        var date: Date
        var outcome: LogOutcome
        var minutes: Int
        var note: String?

        init(
            id: UUID = UUID(),
            updatedAt: Date = .now,
            isDeleted: Bool = false,
            areaId: UUID,
            itemId: UUID? = nil,
            date: Date = .now,
            outcome: LogOutcome,
            minutes: Int = 0,
            note: String? = nil
        ) {
            self.id = id
            self.updatedAt = updatedAt
            self.isDeleted = isDeleted
            self.areaId = areaId
            self.itemId = itemId
            self.date = date
            self.outcome = outcome
            self.minutes = minutes
            self.note = note
        }
    }

    @Model
    final class Target {
        var id: UUID
        var updatedAt: Date
        var isDeleted: Bool
        var areaId: UUID
        var weeklyMinutes: Int?
        var weeklySessions: Int?
        var setAt: Date

        init(
            id: UUID = UUID(),
            updatedAt: Date = .now,
            isDeleted: Bool = false,
            areaId: UUID,
            weeklyMinutes: Int? = nil,
            weeklySessions: Int? = nil,
            setAt: Date = .now
        ) {
            self.id = id
            self.updatedAt = updatedAt
            self.isDeleted = isDeleted
            self.areaId = areaId
            self.weeklyMinutes = weeklyMinutes
            self.weeklySessions = weeklySessions
            self.setAt = setAt
        }
    }
}

@MainActor
final class TombstoneMigrationTests: XCTestCase {
    private let liveAreaID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let deletedAreaID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let liveItemID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    private let deletedItemID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    private let liveInboxID = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
    private let deletedInboxID = UUID(uuidString: "00000000-0000-0000-0000-000000000006")!
    private let liveBlockLogID = UUID(uuidString: "00000000-0000-0000-0000-000000000007")!
    private let deletedBlockLogID = UUID(uuidString: "00000000-0000-0000-0000-000000000008")!
    private let liveBlockEntryID = UUID(uuidString: "00000000-0000-0000-0000-000000000009")!
    private let deletedBlockEntryID = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let liveUnplannedID = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    private let deletedUnplannedID = UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!
    private let liveTargetID = UUID(uuidString: "00000000-0000-0000-0000-00000000000D")!
    private let deletedTargetID = UUID(uuidString: "00000000-0000-0000-0000-00000000000E")!

    private let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let deletedUpdatedAt = Date(timeIntervalSince1970: 1_700_000_600)
    private let createdAt = Date(timeIntervalSince1970: 1_699_000_000)
    private let eventStart = Date(timeIntervalSince1970: 1_700_001_800)

    func testLegacyStoredIsDeletedMigratesForEveryModelAndRemainsWritable() throws {
        let fileManager = FileManager.default
        let folderURL = fileManager.temporaryDirectory
            .appendingPathComponent("Cadence-TombstoneMigration-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: folderURL) }
        let storeURL = folderURL.appendingPathComponent("synthetic-store.sqlite")

        try seedLegacyStore(at: storeURL)

        let container = try currentContainer(at: storeURL)
        let context = ModelContext(container)
        let areas = try fetch(Area.self, in: context)
        let items = try fetch(Item.self, in: context)
        let inbox = try fetch(InboxNote.self, in: context)
        let blockLogs = try fetch(BlockLog.self, in: context)
        let blockEntries = try fetch(BlockEntry.self, in: context)
        let unplanned = try fetch(UnplannedLog.self, in: context)
        let targets = try fetch(Target.self, in: context)

        XCTAssertEqual(areas.count, 2)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(inbox.count, 2)
        XCTAssertEqual(blockLogs.count, 2)
        XCTAssertEqual(blockEntries.count, 2)
        XCTAssertEqual(unplanned.count, 2)
        XCTAssertEqual(targets.count, 2)

        let areaByID = Dictionary(uniqueKeysWithValues: areas.map { ($0.id, $0) })
        XCTAssertEqual(Set(areaByID.keys), Set([liveAreaID, deletedAreaID]))
        XCTAssertEqual(areaByID[liveAreaID]?.updatedAt, updatedAt)
        XCTAssertEqual(areaByID[deletedAreaID]?.updatedAt, deletedUpdatedAt)
        XCTAssertFalse(try XCTUnwrap(areaByID[liveAreaID]).isDeleted)
        XCTAssertFalse(try XCTUnwrap(areaByID[liveAreaID]).isTombstoned)
        XCTAssertTrue(try XCTUnwrap(areaByID[deletedAreaID]).isDeleted)
        XCTAssertTrue(try XCTUnwrap(areaByID[deletedAreaID]).isTombstoned)
        XCTAssertEqual(areaByID[liveAreaID]?.name, "Planning")
        XCTAssertEqual(areaByID[deletedAreaID]?.googleCalendarId, "calendar-deleted")
        XCTAssertEqual(areaByID[liveAreaID]?.createdAt, createdAt)

        let itemByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        XCTAssertEqual(Set(itemByID.keys), Set([liveItemID, deletedItemID]))
        XCTAssertEqual(itemByID[liveItemID]?.updatedAt, updatedAt)
        XCTAssertEqual(itemByID[deletedItemID]?.updatedAt, deletedUpdatedAt)
        XCTAssertFalse(try XCTUnwrap(itemByID[liveItemID]).isDeleted)
        XCTAssertFalse(try XCTUnwrap(itemByID[liveItemID]).isTombstoned)
        XCTAssertTrue(try XCTUnwrap(itemByID[deletedItemID]).isDeleted)
        XCTAssertTrue(try XCTUnwrap(itemByID[deletedItemID]).isTombstoned)
        XCTAssertEqual(itemByID[liveItemID]?.kind, .task)
        XCTAssertEqual(itemByID[liveItemID]?.title, "Prepare migration")
        XCTAssertEqual(itemByID[liveItemID]?.areaId, liveAreaID)
        XCTAssertEqual(itemByID[liveItemID]?.fullVersion, "Detailed steps")
        XCTAssertEqual(itemByID[liveItemID]?.easyVersion, "Start with one step")
        XCTAssertEqual(itemByID[liveItemID]?.status, .done)
        XCTAssertEqual(itemByID[liveItemID]?.notes, "Keep the old record readable")
        XCTAssertEqual(itemByID[liveItemID]?.createdAt, createdAt)

        let inboxByID = Dictionary(uniqueKeysWithValues: inbox.map { ($0.id, $0) })
        XCTAssertEqual(Set(inboxByID.keys), Set([liveInboxID, deletedInboxID]))
        XCTAssertEqual(inboxByID[liveInboxID]?.updatedAt, updatedAt)
        XCTAssertEqual(inboxByID[deletedInboxID]?.updatedAt, deletedUpdatedAt)
        XCTAssertFalse(try XCTUnwrap(inboxByID[liveInboxID]).isDeleted)
        XCTAssertFalse(try XCTUnwrap(inboxByID[liveInboxID]).isTombstoned)
        XCTAssertTrue(try XCTUnwrap(inboxByID[deletedInboxID]).isDeleted)
        XCTAssertTrue(try XCTUnwrap(inboxByID[deletedInboxID]).isTombstoned)
        XCTAssertEqual(inboxByID[liveInboxID]?.rawText, "Review the migration")
        XCTAssertEqual(inboxByID[liveInboxID]?.state, .sorted)
        XCTAssertEqual(inboxByID[liveInboxID]?.resultingItemId, liveItemID)
        XCTAssertEqual(inboxByID[liveInboxID]?.sortedAt, eventStart)
        XCTAssertEqual(inboxByID[liveInboxID]?.failureCount, 2)
        XCTAssertEqual(inboxByID[liveInboxID]?.isLowConfidence, true)

        let blockLogByID = Dictionary(uniqueKeysWithValues: blockLogs.map { ($0.id, $0) })
        XCTAssertEqual(Set(blockLogByID.keys), Set([liveBlockLogID, deletedBlockLogID]))
        XCTAssertEqual(blockLogByID[liveBlockLogID]?.updatedAt, updatedAt)
        XCTAssertEqual(blockLogByID[deletedBlockLogID]?.updatedAt, deletedUpdatedAt)
        XCTAssertFalse(try XCTUnwrap(blockLogByID[liveBlockLogID]).isDeleted)
        XCTAssertFalse(try XCTUnwrap(blockLogByID[liveBlockLogID]).isTombstoned)
        XCTAssertTrue(try XCTUnwrap(blockLogByID[deletedBlockLogID]).isDeleted)
        XCTAssertTrue(try XCTUnwrap(blockLogByID[deletedBlockLogID]).isTombstoned)
        XCTAssertEqual(blockLogByID[liveBlockLogID]?.googleEventId, "event-migration")
        XCTAssertEqual(blockLogByID[liveBlockLogID]?.eventStart, eventStart)
        XCTAssertEqual(blockLogByID[liveBlockLogID]?.areaId, liveAreaID)
        XCTAssertEqual(blockLogByID[liveBlockLogID]?.plannedMinutes, 50)
        XCTAssertEqual(blockLogByID[liveBlockLogID]?.state, .full)
        XCTAssertEqual(blockLogByID[liveBlockLogID]?.loggedMinutes, 45)
        XCTAssertEqual(blockLogByID[liveBlockLogID]?.note, "Focused work")

        let blockEntryByID = Dictionary(uniqueKeysWithValues: blockEntries.map { ($0.id, $0) })
        XCTAssertEqual(Set(blockEntryByID.keys), Set([liveBlockEntryID, deletedBlockEntryID]))
        XCTAssertEqual(blockEntryByID[liveBlockEntryID]?.updatedAt, updatedAt)
        XCTAssertEqual(blockEntryByID[deletedBlockEntryID]?.updatedAt, deletedUpdatedAt)
        XCTAssertFalse(try XCTUnwrap(blockEntryByID[liveBlockEntryID]).isDeleted)
        XCTAssertFalse(try XCTUnwrap(blockEntryByID[liveBlockEntryID]).isTombstoned)
        XCTAssertTrue(try XCTUnwrap(blockEntryByID[deletedBlockEntryID]).isDeleted)
        XCTAssertTrue(try XCTUnwrap(blockEntryByID[deletedBlockEntryID]).isTombstoned)
        XCTAssertEqual(blockEntryByID[liveBlockEntryID]?.blockLogId, liveBlockLogID)
        XCTAssertEqual(blockEntryByID[liveBlockEntryID]?.itemId, liveItemID)
        XCTAssertEqual(blockEntryByID[liveBlockEntryID]?.outcome, .full)
        XCTAssertEqual(blockEntryByID[liveBlockEntryID]?.minutes, 45)

        let unplannedByID = Dictionary(uniqueKeysWithValues: unplanned.map { ($0.id, $0) })
        XCTAssertEqual(Set(unplannedByID.keys), Set([liveUnplannedID, deletedUnplannedID]))
        XCTAssertEqual(unplannedByID[liveUnplannedID]?.updatedAt, updatedAt)
        XCTAssertEqual(unplannedByID[deletedUnplannedID]?.updatedAt, deletedUpdatedAt)
        XCTAssertFalse(try XCTUnwrap(unplannedByID[liveUnplannedID]).isDeleted)
        XCTAssertFalse(try XCTUnwrap(unplannedByID[liveUnplannedID]).isTombstoned)
        XCTAssertTrue(try XCTUnwrap(unplannedByID[deletedUnplannedID]).isDeleted)
        XCTAssertTrue(try XCTUnwrap(unplannedByID[deletedUnplannedID]).isTombstoned)
        XCTAssertEqual(unplannedByID[liveUnplannedID]?.areaId, liveAreaID)
        XCTAssertEqual(unplannedByID[liveUnplannedID]?.itemId, liveItemID)
        XCTAssertEqual(unplannedByID[liveUnplannedID]?.date, eventStart)
        XCTAssertEqual(unplannedByID[liveUnplannedID]?.outcome, .easy)
        XCTAssertEqual(unplannedByID[liveUnplannedID]?.minutes, 20)
        XCTAssertEqual(unplannedByID[liveUnplannedID]?.note, "Unplanned but useful")

        let targetByID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0) })
        XCTAssertEqual(Set(targetByID.keys), Set([liveTargetID, deletedTargetID]))
        XCTAssertEqual(targetByID[liveTargetID]?.updatedAt, updatedAt)
        XCTAssertEqual(targetByID[deletedTargetID]?.updatedAt, deletedUpdatedAt)
        XCTAssertFalse(try XCTUnwrap(targetByID[liveTargetID]).isDeleted)
        XCTAssertFalse(try XCTUnwrap(targetByID[liveTargetID]).isTombstoned)
        XCTAssertTrue(try XCTUnwrap(targetByID[deletedTargetID]).isDeleted)
        XCTAssertTrue(try XCTUnwrap(targetByID[deletedTargetID]).isTombstoned)
        XCTAssertEqual(targetByID[liveTargetID]?.areaId, liveAreaID)
        XCTAssertEqual(targetByID[liveTargetID]?.weeklyMinutes, 180)
        XCTAssertEqual(targetByID[liveTargetID]?.weeklySessions, 4)
        XCTAssertEqual(targetByID[liveTargetID]?.setAt, createdAt)

        let json = String(decoding: exportJSON(context: context), as: UTF8.self)
        XCTAssertTrue(json.contains("\"isDeleted\""))
        XCTAssertFalse(json.contains("isTombstoned"))

        let area = try XCTUnwrap(areaByID[liveAreaID])
        area.isDeleted = true
        try context.save()

        let afterDeleteContext = ModelContext(container)
        let afterDeleteAreas = try fetch(Area.self, in: afterDeleteContext)
        let afterDeleteArea = try XCTUnwrap(afterDeleteAreas.first { $0.id == liveAreaID })
        XCTAssertTrue(afterDeleteArea.isDeleted)
        XCTAssertTrue(afterDeleteArea.isTombstoned)

        afterDeleteArea.isDeleted = false
        try afterDeleteContext.save()

        let afterUndoContext = ModelContext(container)
        let afterUndoAreas = try fetch(Area.self, in: afterUndoContext)
        let afterUndoArea = try XCTUnwrap(afterUndoAreas.first { $0.id == liveAreaID })
        XCTAssertFalse(afterUndoArea.isDeleted)
        XCTAssertFalse(afterUndoArea.isTombstoned)
    }

    private func seedLegacyStore(at url: URL) throws {
        try autoreleasepool {
            let configuration = ModelConfiguration(schema: LegacyTombstoneSchema.schema, url: url)
            let container = try ModelContainer(for: LegacyTombstoneSchema.schema, configurations: [configuration])
            let context = container.mainContext

            context.insert(LegacyTombstoneSchema.Area(
                id: liveAreaID, updatedAt: updatedAt, name: "Planning", colorHex: "#5C9B96",
                symbolName: "calendar", sortOrder: 1, googleCalendarId: "calendar-live",
                createdAt: createdAt
            ))
            context.insert(LegacyTombstoneSchema.Area(
                id: deletedAreaID, updatedAt: deletedUpdatedAt, isDeleted: true, name: "Old planning",
                colorHex: "#888888", symbolName: "archivebox", sortOrder: 2,
                googleCalendarId: "calendar-deleted", isArchived: true, createdAt: createdAt
            ))
            context.insert(LegacyTombstoneSchema.Item(
                id: liveItemID, updatedAt: updatedAt, kind: .task, title: "Prepare migration",
                areaId: liveAreaID, fullVersion: "Detailed steps", easyVersion: "Start with one step",
                dueDate: eventStart, status: .done, notes: "Keep the old record readable",
                createdAt: createdAt, completedAt: eventStart
            ))
            context.insert(LegacyTombstoneSchema.Item(
                id: deletedItemID, updatedAt: deletedUpdatedAt, isDeleted: true, kind: .activity,
                title: "Removed activity", areaId: deletedAreaID, status: .dropped, createdAt: createdAt
            ))
            context.insert(LegacyTombstoneSchema.InboxNote(
                id: liveInboxID, updatedAt: updatedAt, rawText: "Review the migration", createdAt: createdAt,
                state: .sorted, resultingItemId: liveItemID, sortedAt: eventStart, failureCount: 2,
                isLowConfidence: true
            ))
            context.insert(LegacyTombstoneSchema.InboxNote(
                id: deletedInboxID, updatedAt: deletedUpdatedAt, isDeleted: true, rawText: "Discarded note",
                createdAt: createdAt, state: .failed
            ))
            context.insert(LegacyTombstoneSchema.BlockLog(
                id: liveBlockLogID, updatedAt: updatedAt, googleEventId: "event-migration",
                eventStart: eventStart, areaId: liveAreaID, plannedMinutes: 50, state: .full,
                loggedMinutes: 45, note: "Focused work"
            ))
            context.insert(LegacyTombstoneSchema.BlockLog(
                id: deletedBlockLogID, updatedAt: deletedUpdatedAt, isDeleted: true,
                googleEventId: "event-deleted", eventStart: eventStart, areaId: deletedAreaID
            ))
            context.insert(LegacyTombstoneSchema.BlockEntry(
                id: liveBlockEntryID, updatedAt: updatedAt, blockLogId: liveBlockLogID,
                itemId: liveItemID, outcome: .full, minutes: 45
            ))
            context.insert(LegacyTombstoneSchema.BlockEntry(
                id: deletedBlockEntryID, updatedAt: deletedUpdatedAt, isDeleted: true,
                blockLogId: deletedBlockLogID, outcome: .skipped
            ))
            context.insert(LegacyTombstoneSchema.UnplannedLog(
                id: liveUnplannedID, updatedAt: updatedAt, areaId: liveAreaID, itemId: liveItemID,
                date: eventStart, outcome: .easy, minutes: 20, note: "Unplanned but useful"
            ))
            context.insert(LegacyTombstoneSchema.UnplannedLog(
                id: deletedUnplannedID, updatedAt: deletedUpdatedAt, isDeleted: true,
                areaId: deletedAreaID, date: eventStart, outcome: .planned, note: "Removed"
            ))
            context.insert(LegacyTombstoneSchema.Target(
                id: liveTargetID, updatedAt: updatedAt, areaId: liveAreaID, weeklyMinutes: 180,
                weeklySessions: 4, setAt: createdAt
            ))
            context.insert(LegacyTombstoneSchema.Target(
                id: deletedTargetID, updatedAt: deletedUpdatedAt, isDeleted: true,
                areaId: deletedAreaID, weeklyMinutes: 60, weeklySessions: 1, setAt: createdAt
            ))
            try context.save()
        }
    }

    private func currentContainer(at url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: CadenceSchema.schema, url: url)
        return try ModelContainer(for: CadenceSchema.schema, configurations: [configuration])
    }

    private func fetch<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }
}

import Foundation
import SwiftData

public func fetchAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) -> [T] {
    do { return try context.fetch(FetchDescriptor<T>()) } catch { return [] }
}

public func live(_ models: [some SyncedModel]) -> [some SyncedModel] {
    models.filter { !$0.isDeleted }
}

// MARK: - Areas

public func allAreas(in context: ModelContext) -> [Area] {
    fetchAll(Area.self, in: context)
        .filter { !$0.isDeleted }
        .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
}

public func visibleAreas(in context: ModelContext) -> [Area] {
    allAreas(in: context).filter { !$0.isArchived }
}

public func classesArea(in context: ModelContext) -> Area? {
    allAreas(in: context).first { $0.isClassesCalendar }
}

public func area(withId id: UUID, in context: ModelContext) -> Area? {
    allAreas(in: context).first { $0.id == id }
}

// MARK: - Items

public func allItems(in context: ModelContext) -> [Item] {
    fetchAll(Item.self, in: context).filter { !$0.isDeleted }
}

public func items(forArea areaId: UUID, in context: ModelContext) -> [Item] {
    allItems(in: context).filter { $0.areaId == areaId }
}

public func openTasks(in context: ModelContext) -> [Item] {
    allItems(in: context)
        .filter { $0.kind == .task && $0.status == .open }
        .sorted {
            switch ($0.dueDate, $1.dueDate) {
            case let (a?, b?): return a != b ? a < b : $0.createdAt < $1.createdAt
            case (nil, nil): return $0.createdAt < $1.createdAt
            case (nil, _): return false
            case (_, nil): return true
            }
        }
}

public func activities(forArea areaId: UUID, in context: ModelContext) -> [Item] {
    items(forArea: areaId, in: context)
        .filter { $0.kind == .activity }
        .sorted { $0.title < $1.title }
}

public func item(withId id: UUID, in context: ModelContext) -> Item? {
    allItems(in: context).first { $0.id == id }
}

// MARK: - Logs

public func allBlockEntries(in context: ModelContext) -> [BlockEntry] {
    fetchAll(BlockEntry.self, in: context).filter { !$0.isDeleted }
}

public func blockEntries(forLogId logId: UUID, in context: ModelContext) -> [BlockEntry] {
    allBlockEntries(in: context).filter { $0.blockLogId == logId }
}

public func allBlockLogs(in context: ModelContext) -> [BlockLog] {
    fetchAll(BlockLog.self, in: context).filter { !$0.isDeleted }
}

public func allUnplannedLogs(in context: ModelContext) -> [UnplannedLog] {
    fetchAll(UnplannedLog.self, in: context).filter { !$0.isDeleted }
}

public func allTargets(in context: ModelContext) -> [Target] {
    fetchAll(Target.self, in: context).filter { !$0.isDeleted }
}
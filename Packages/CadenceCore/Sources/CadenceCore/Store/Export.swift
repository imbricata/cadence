import Foundation
import SwiftData

public struct ExportBundle: Codable, Sendable {
    public var areas: [AreaSnapshot]
    public var items: [ItemSnapshot]
    public var inbox: [InboxNoteSnapshot]
    public var blockLogs: [BlockLogSnapshot]
    public var blockEntries: [BlockEntrySnapshot]
    public var unplanned: [UnplannedLogSnapshot]
    public var targets: [TargetSnapshot]
}

public func exportBundle(context: ModelContext) -> ExportBundle {
    ExportBundle(
        areas: fetchAll(Area.self, in: context).map(AreaSnapshot.init),
        items: fetchAll(Item.self, in: context).map(ItemSnapshot.init),
        inbox: fetchAll(InboxNote.self, in: context).map(InboxNoteSnapshot.init),
        blockLogs: fetchAll(BlockLog.self, in: context).map(BlockLogSnapshot.init),
        blockEntries: fetchAll(BlockEntry.self, in: context).map(BlockEntrySnapshot.init),
        unplanned: fetchAll(UnplannedLog.self, in: context).map(UnplannedLogSnapshot.init),
        targets: fetchAll(Target.self, in: context).map(TargetSnapshot.init)
    )
}

public func exportJSON(context: ModelContext) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return (try? encoder.encode(exportBundle(context: context))) ?? Data()
}
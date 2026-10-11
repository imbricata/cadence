import Foundation
import SwiftData

@Model
public final class UnplannedLog: SyncedModel {
    public var id: UUID
    public var updatedAt: Date
    public var isDeleted: Bool

    public var areaId: UUID
    public var itemId: UUID?
    public var date: Date
    public var outcome: LogOutcome
    public var minutes: Int
    public var note: String?

    public init(
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
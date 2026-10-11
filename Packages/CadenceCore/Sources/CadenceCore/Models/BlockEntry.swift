import Foundation
import SwiftData

@Model
public final class BlockEntry: SyncedModel {
    public var id: UUID
    public var updatedAt: Date
    public var isDeleted: Bool

    public var blockLogId: UUID
    public var itemId: UUID?
    public var outcome: LogOutcome
    public var minutes: Int

    public init(
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
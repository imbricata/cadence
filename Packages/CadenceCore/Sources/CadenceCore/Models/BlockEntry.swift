import Foundation
import SwiftData

@Model
public final class BlockEntry: SyncedModel {
    public var id: UUID
    public var updatedAt: Date
    @Attribute(originalName: "isDeleted") public var isTombstoned: Bool = false
    // A stored `isDeleted` collides with Core Data's deletion flag. Preserve the sync-facing API.
    public var isDeleted: Bool {
        get { isTombstoned }
        set { isTombstoned = newValue }
    }

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
        self.isTombstoned = isDeleted
        self.blockLogId = blockLogId
        self.itemId = itemId
        self.outcome = outcome
        self.minutes = minutes
    }
}

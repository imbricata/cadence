import Foundation
import SwiftData

@Model
public final class BlockLog: SyncedModel {
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

    public init(
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
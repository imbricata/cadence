import Foundation
import SwiftData

@Model
public final class Area: SyncedModel {
    public var id: UUID
    public var updatedAt: Date
    @Attribute(originalName: "isDeleted") public var isTombstoned: Bool = false
    // A stored `isDeleted` collides with Core Data's deletion flag. Preserve the sync-facing API.
    public var isDeleted: Bool {
        get { isTombstoned }
        set { isTombstoned = newValue }
    }

    public var name: String
    public var colorHex: String
    public var symbolName: String
    public var sortOrder: Int
    public var googleCalendarId: String
    public var isClassesCalendar: Bool
    public var isArchived: Bool
    public var createdAt: Date

    public init(
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
        self.isTombstoned = isDeleted
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

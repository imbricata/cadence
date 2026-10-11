import Foundation
import SwiftData

@Model
public final class Target: SyncedModel {
    public var id: UUID
    public var updatedAt: Date
    public var isDeleted: Bool

    public var areaId: UUID
    public var weeklyMinutes: Int?
    public var weeklySessions: Int?
    public var setAt: Date

    public init(
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
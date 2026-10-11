import Foundation
import SwiftData

@Model
public final class Item: SyncedModel {
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

    public init(
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
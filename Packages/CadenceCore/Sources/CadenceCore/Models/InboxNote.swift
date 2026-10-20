import Foundation
import SwiftData

@Model
public final class InboxNote: SyncedModel {
    public var id: UUID
    public var updatedAt: Date
    public var isDeleted: Bool

    public var rawText: String
    public var createdAt: Date
    public var state: InboxNoteState
    public var resultingItemId: UUID?
    public var sortedAt: Date?
    public var failureCount: Int
    public var isLowConfidence: Bool = false

    public init(
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
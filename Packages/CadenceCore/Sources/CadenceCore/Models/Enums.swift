import Foundation

public enum ItemKind: String, Codable, CaseIterable, Sendable {
    case task
    case activity
}

public enum ItemStatus: String, Codable, CaseIterable, Sendable {
    case open
    case done
    case dropped
}

public enum InboxNoteState: String, Codable, CaseIterable, Sendable {
    case pending
    case sorted
    case failed
}

public enum BlockLogState: String, Codable, CaseIterable, Sendable {
    case unlogged
    case full
    case easy
    case skipped
}

public enum LogOutcome: String, Codable, CaseIterable, Sendable {
    case full
    case easy
    case skipped

    public var weight: Double {
        switch self {
        case .full: return 1.0
        case .easy: return 0.75
        case .skipped: return 0.0
        }
    }
}

/// Fields shared by every model that is synced to Google Drive.
public protocol SyncedModel: AnyObject {
    var id: UUID { get set }
    var updatedAt: Date { get set }
    var isDeleted: Bool { get set }
}
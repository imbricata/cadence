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
    /// In the block but not logged yet (a plan, never counted as work).
    case planned
    case full
    case easy
    case skipped

    public var weight: Double {
        switch self {
        case .full: return 1.0
        case .easy: return 0.75
        case .skipped, .planned: return 0.0
        }
    }

    /// True for outcomes that represent time actually spent.
    public var countsAsWork: Bool { self == .full || self == .easy }

    public init(_ state: BlockLogState) {
        switch state {
        case .full: self = .full
        case .easy: self = .easy
        case .skipped: self = .skipped
        case .unlogged: self = .planned
        }
    }
}

/// Fields shared by every model that is synced to Google Drive.
public protocol SyncedModel: AnyObject {
    var id: UUID { get set }
    var updatedAt: Date { get set }
    var isDeleted: Bool { get set }
}
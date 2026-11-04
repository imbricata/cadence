import Foundation
import SwiftData

/// Date-only deadlines use the user's calendar, including 23/25-hour days.
public enum TaskBucket: String, CaseIterable, Identifiable {
    case overdue = "Overdue"
    case today = "Today"
    case upcoming = "Upcoming"
    case undated = "No due date"

    public var id: String { rawValue }

    public static func classify(dueDate: Date?, now: Date = .now, calendar: Calendar = .current) -> TaskBucket {
        guard let dueDate else { return .undated }
        if dueDate < calendar.startOfDay(for: now) { return .overdue }
        if calendar.isDate(dueDate, inSameDayAs: now) { return .today }
        return .upcoming
    }
}

public enum TaskAgenda {
    /// A single definition of actionable tasks, shared by Today and the task list.
    public static func openTasks(items: [Item], areas: [Area]) -> [Item] {
        let active = Set(areas.filter { !$0.isDeleted && !$0.isArchived && !$0.isClassesCalendar }.map(\.id))
        return items.filter { !$0.isDeleted && $0.kind == .task && $0.status == .open && active.contains($0.areaId) }
            .sorted(by: ordered)
    }

    public static func ordered(_ a: Item, _ b: Item) -> Bool {
        if a.dueDate != b.dueDate { return (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture) }
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.id.uuidString < b.id.uuidString
    }
}

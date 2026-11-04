import XCTest
import SwiftData
import CadenceCore

@MainActor
final class TaskAgendaTests: XCTestCase {
    func testDueDatesRespectLocalDayAcrossDaylightSaving() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Madrid"))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 29)))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        XCTAssertEqual(tomorrow.timeIntervalSince(today), 23 * 3600)
        XCTAssertEqual(TaskBucket.classify(dueDate: today.addingTimeInterval(-1), now: today, calendar: calendar), .overdue)
        XCTAssertEqual(TaskBucket.classify(dueDate: tomorrow.addingTimeInterval(-1), now: today, calendar: calendar), .today)
        XCTAssertEqual(TaskBucket.classify(dueDate: tomorrow, now: today, calendar: calendar), .upcoming)
        XCTAssertEqual(TaskBucket.classify(dueDate: nil, now: today, calendar: calendar), .undated)
    }

    func testAgendaExcludesHiddenAreasCompletedTasksAndActivities() throws {
        let store = try AppStore.inMemory()
        let active = createArea(store, name: "Work", colorHex: "#5C9B96", symbolName: "briefcase")
        let archived = createArea(store, name: "Old", colorHex: "#5C9B96", symbolName: "folder")
        let deleted = createArea(store, name: "Deleted", colorHex: "#5C9B96", symbolName: "folder")
        let classes = createArea(store, name: "Classes", colorHex: "#888888", symbolName: "book", isClasses: true)
        updateArea(store, archived, isArchived: true)
        deleteArea(store, deleted)
        let undated = createItem(store, kind: .task, title: "Later", areaId: active.id)
        let first = createItem(store, kind: .task, title: "First", areaId: active.id, dueDate: .now.addingTimeInterval(-86400))
        let second = createItem(store, kind: .task, title: "Second", areaId: active.id, dueDate: .now)
        for area in [archived, deleted, classes] { createItem(store, kind: .task, title: "Hidden", areaId: area.id) }
        createItem(store, kind: .task, title: "Orphan", areaId: UUID())
        createItem(store, kind: .activity, title: "Work", areaId: active.id)
        let done = createItem(store, kind: .task, title: "Done", areaId: active.id)
        updateItem(store, done, status: .done)
        let dropped = createItem(store, kind: .task, title: "Dropped", areaId: active.id)
        updateItem(store, dropped, status: .dropped)
        let removed = createItem(store, kind: .task, title: "Removed", areaId: active.id)
        deleteItem(store, removed)
        XCTAssertTrue(removed.isDeleted)
        XCTAssertTrue(deleted.isDeleted)
        let agenda = TaskAgenda.openTasks(items: fetchAll(Item.self, in: store.context), areas: [active, archived, deleted, classes])
        XCTAssertEqual(agenda.map(\.id), [first.id, second.id, undated.id], "Visible: \(agenda.map(\.title))")
    }
}

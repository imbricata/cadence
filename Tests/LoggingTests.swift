import XCTest
import SwiftData
import CadenceCore

@MainActor
final class LoggingTests: XCTestCase {
    var store: AppStore!
    var area: Area!
    var task: Item!
    var activity: Item!
    var ref: BlockRef!
    let start = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: .now))!.addingTimeInterval(9 * 3600)

    override func setUp() async throws {
        store = try AppStore.inMemory()
        area = createArea(store, name: "Work", colorHex: "#5C9B96", symbolName: "briefcase", calendarId: "cal-work")
        task = createItem(store, kind: .task, title: "Write report", areaId: area.id)
        activity = createItem(store, kind: .activity, title: "Deep work", areaId: area.id)
        ref = BlockRef(googleEventId: "evt1", eventStart: start, areaId: area.id, plannedMinutes: 60)
    }

    private func snapshot(events: [CalendarEvent] = []) -> InsightSnapshot {
        computeInsights(context: store.context, events: events)
    }

    func testOpeningABlockCreatesNothing() {
        XCTAssertNil(findBlockLog(store, googleEventId: "evt1", eventStart: start))
        XCTAssertTrue(fetchAll(BlockLog.self, in: store.context).isEmpty)
    }

    func testPlanningDoesNotCompleteTasksOrCountAsWork() {
        planItem(store, item: task, in: ref)
        planItem(store, item: activity, in: ref)
        XCTAssertEqual(task.status, .open)
        let log = findBlockLog(store, googleEventId: "evt1", eventStart: start)!
        XCTAssertEqual(log.state, .unlogged)
        let snap = snapshot()
        XCTAssertEqual(snap.areas.first?.rawMinutes, 0)
        XCTAssertEqual(snap.activities.first?.rawMinutes, 0)
    }

    func testLoggingFullCompletesTaskAndCountsMinutes() {
        planItem(store, item: task, in: ref)
        planItem(store, item: activity, in: ref)
        logBlock(store, ref, state: .full)
        XCTAssertEqual(task.status, .done)
        XCTAssertNotNil(task.completedAt)
        let snap = snapshot()
        XCTAssertEqual(snap.areas.first?.rawMinutes, 60)
        XCTAssertEqual(snap.activities.first?.rawMinutes, 30)
    }

    func testEasyAndSkippedKeepTasksOpen() {
        planItem(store, item: task, in: ref)
        logBlock(store, ref, state: .easy)
        XCTAssertEqual(task.status, .open)
        XCTAssertEqual(snapshot().areas.first?.rawMinutes, 30)
        logBlock(store, ref, state: .skipped)
        XCTAssertEqual(task.status, .open)
        XCTAssertEqual(snapshot().areas.first?.rawMinutes, 0)
    }

    func testClearingLogReopensTaskAndRemovesWork() {
        planItem(store, item: task, in: ref)
        logBlock(store, ref, state: .full)
        XCTAssertEqual(task.status, .done)
        logBlock(store, ref, state: .unlogged)
        XCTAssertEqual(task.status, .open)
        XCTAssertNil(task.completedAt)
        XCTAssertEqual(snapshot().areas.first?.rawMinutes, 0)
        XCTAssertEqual(blockEntries(forLogId: findBlockLog(store, googleEventId: "evt1", eventStart: start)!.id, in: store.context).count, 1)
    }

    func testEmptyBlockLoggedCountsAsDidArea() {
        logBlock(store, ref, state: .full)
        XCTAssertEqual(snapshot().areas.first?.rawMinutes, 60)
    }

    func testPerItemOverride() {
        planItem(store, item: task, in: ref)
        planItem(store, item: activity, in: ref)
        logBlock(store, ref, state: .full)
        let entry = blockEntries(forLogId: findBlockLog(store, googleEventId: "evt1", eventStart: start)!.id, in: store.context)
            .first { $0.itemId == task.id }!
        setEntryOutcome(store, entry, outcome: .skipped, blockMinutes: 60)
        XCTAssertEqual(task.status, .open)
        XCTAssertEqual(snapshot().areas.first?.rawMinutes, 30)
    }

    func testRemovingAFullItemReopensTask() {
        planItem(store, item: task, in: ref)
        logBlock(store, ref, state: .full)
        unplanItem(store, itemId: task.id, in: ref)
        XCTAssertEqual(task.status, .open)
    }

    func testPlanningIntoLoggedBlockTakesBlockOutcome() {
        logBlock(store, ref, state: .easy)
        let e = planItem(store, item: activity, in: ref)
        XCTAssertEqual(e.outcome, .easy)
        XCTAssertGreaterThan(e.minutes, 0)
    }

    func testSparseDaysLowerForm() throws {
        // 5 weeks of one 60-minute Full session per week should read far below "60 min/day".
        for w in 0..<5 {
            let day = Calendar.current.date(byAdding: .day, value: -(w * 7 + 1), to: .now)!
            addUnplannedLog(store, areaId: area.id, date: day, outcome: .full, minutes: 60)
        }
        let stat = try XCTUnwrap(snapshot().areas.first)
        XCTAssertLessThan(stat.baselineDaily, 20)
        XCTAssertGreaterThan(stat.baselineDaily, 5)
    }

    func testTargetIsFormReference() throws {
        upsertTarget(store, areaId: area.id, weeklyMinutes: 140, weeklySessions: nil)
        for d in 1...7 {
            let day = Calendar.current.date(byAdding: .day, value: -d, to: .now)!
            addUnplannedLog(store, areaId: area.id, date: day, outcome: .full, minutes: 20)
        }
        let stat = try XCTUnwrap(snapshot().areas.first)
        XCTAssertEqual(stat.referenceDaily, 20, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(stat.formPercent), 100, accuracy: 1)
    }

    func testFollowThroughSumsAndIgnoresFutureAndClasses() {
        let now = Date.now
        func event(_ id: String, hoursAgo: Double, cal: String = "cal-work", allDay: Bool = false) -> CalendarEvent {
            let s = now.addingTimeInterval(-hoursAgo * 3600)
            return CalendarEvent(id: id, summary: "x", start: s, end: s.addingTimeInterval(3600), calendarId: cal, isAllDay: allDay, isCadenceBlock: true)
        }
        let events = [
            event("a", hoursAgo: 30), event("b", hoursAgo: 28),
            event("future", hoursAgo: -5),
            event("class", hoursAgo: 29, cal: "classes"),
            event("allday", hoursAgo: 27, allDay: true)
        ]
        let a = BlockRef(googleEventId: "a", eventStart: events[0].start, areaId: area.id, plannedMinutes: 60)
        logBlock(store, a, state: .full)
        let b = BlockRef(googleEventId: "b", eventStart: events[1].start, areaId: area.id, plannedMinutes: 60)
        logBlock(store, b, state: .easy)
        let ft = snapshot(events: events).followThrough
        XCTAssertEqual(ft.planned, 2)
        XCTAssertEqual(ft.loggedWeight, 1.75, accuracy: 0.001)
        XCTAssertEqual(ft.percent ?? 0, 87.5, accuracy: 0.01)
        XCTAssertEqual(ft.days.reduce(0) { $0 + $1.planned }, 2)
    }

    func testPlannedOnlyBlockInPastCountsAsMissed() {
        let ev = CalendarEvent(id: "m", summary: "x", start: start, end: start.addingTimeInterval(3600), calendarId: "cal-work", isAllDay: false, isCadenceBlock: true)
        planItem(store, item: task, in: ref) // creates an unlogged log, must not make it count as logged
        let ft = snapshot(events: [ev]).followThrough
        XCTAssertEqual(ft.planned, 1)
        XCTAssertEqual(ft.loggedWeight, 0)
    }
}

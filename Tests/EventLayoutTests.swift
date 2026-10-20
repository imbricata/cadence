import XCTest
import CadenceCore

final class EventLayoutTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return c
    }()
    private lazy var day = cal.date(from: DateComponents(year: 2026, month: 10, day: 21))!

    private func at(_ h: Double) -> Date { day.addingTimeInterval(h * 3600) }
    private func ev(_ id: String, _ s: Double, _ e: Double, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: id, summary: id, start: at(s), end: at(e), calendarId: "c", isAllDay: allDay)
    }
    private func lane(_ id: String, _ p: [PositionedEvent]) -> (Int, Int) {
        let x = p.first { $0.id == id }!
        return (x.lane, x.laneCount)
    }

    func testNonOverlappingEventsKeepFullWidth() {
        let p = EventLayout.layout([ev("a", 9, 10), ev("b", 11, 12)], on: day, calendar: cal)
        XCTAssertEqual(lane("a", p).1, 1)
        XCTAssertEqual(lane("b", p).1, 1)
    }

    func testOnlyOverlappingEventsShareWidth() {
        let p = EventLayout.layout([ev("a", 9, 11), ev("b", 10, 12), ev("c", 14, 15)], on: day, calendar: cal)
        XCTAssertEqual(lane("a", p).1, 2)
        XCTAssertEqual(lane("b", p).1, 2)
        XCTAssertEqual(lane("c", p).0, 0)
        XCTAssertEqual(lane("c", p).1, 1, "an unrelated event later in the day stays full width")
        XCTAssertNotEqual(lane("a", p).0, lane("b", p).0)
    }

    func testChainReusesFreedLane() {
        // a overlaps b, b overlaps c, a doesn't touch c -> two lanes, c goes back to lane 0
        let p = EventLayout.layout([ev("a", 9, 10.5), ev("b", 10, 12), ev("c", 10.75, 11.5)], on: day, calendar: cal)
        XCTAssertEqual(lane("a", p).0, 0)
        XCTAssertEqual(lane("b", p).0, 1)
        XCTAssertEqual(lane("c", p).0, 0)
        XCTAssertEqual(p.map(\.laneCount).max(), 2)
    }

    func testThreeWayOverlap() {
        let p = EventLayout.layout([ev("a", 9, 11), ev("b", 9.5, 11), ev("c", 10, 11)], on: day, calendar: cal)
        XCTAssertEqual(Set(p.map(\.lane)), [0, 1, 2])
        XCTAssertTrue(p.allSatisfy { $0.laneCount == 3 })
    }

    func testShortEventsGetMinimumHeight() {
        let p = EventLayout.layout([ev("a", 9, 9.05)], on: day, calendar: cal)
        XCTAssertEqual(p[0].durationMinutes, EventLayout.minimumMinutes, accuracy: 0.01)
    }

    func testEventsSpanningMidnightAreClippedPerDay() {
        let night = ev("n", 22, 26) // 22:00 -> 02:00 next day
        let today = EventLayout.layout([night], on: day, calendar: cal)
        XCTAssertEqual(today[0].endMinute, 1440)
        XCTAssertTrue(today[0].clippedEnd)
        let tomorrow = EventLayout.layout([night], on: cal.date(byAdding: .day, value: 1, to: day)!, calendar: cal)
        XCTAssertEqual(tomorrow[0].startMinute, 0)
        XCTAssertEqual(tomorrow[0].endMinute, 120)
        XCTAssertTrue(tomorrow[0].clippedStart)
    }

    func testAllDayAndDeadlinesAreSplitOut() {
        let events = [
            ev("timed", 9, 10),
            ev("allday", 0, 24, allDay: true),
            CalendarEvent(id: "due", summary: "due", start: at(23.9), end: at(23.9), calendarId: "c")
        ]
        XCTAssertEqual(EventLayout.layout(events, on: day, calendar: cal).map(\.id), ["timed"])
        XCTAssertEqual(Set(EventLayout.allDayItems(events, on: day, calendar: cal).map(\.id)), ["allday", "due"])
        XCTAssertEqual(EventLayout.allDayItems(events, on: cal.date(byAdding: .day, value: 1, to: day)!, calendar: cal).count, 0)
    }

    func testSnapping() {
        XCTAssertEqual(EventLayout.snap(7), 0)
        XCTAssertEqual(EventLayout.snap(8), 15)
        XCTAssertEqual(EventLayout.snap(52), 45)
        XCTAssertEqual(EventLayout.snapDown(59), 45)
    }

    func testMinuteAndDateRoundTrip() {
        let d = EventLayout.date(on: day, minute: 9 * 60 + 45, calendar: cal)
        XCTAssertEqual(EventLayout.minuteOfDay(d, on: day, calendar: cal), 585, accuracy: 0.001)
        XCTAssertEqual(EventLayout.date(on: day, minute: 1440, calendar: cal), cal.date(byAdding: .day, value: 1, to: day))
    }

    func testNextFreeSlotSkipsBusyTime() {
        let events = [ev("a", 9, 10), ev("b", 10, 11.5)]
        XCTAssertEqual(EventLayout.nextFreeSlot(on: day, from: 9 * 60, events: events, calendar: cal), 11.5 * 60)
        XCTAssertEqual(EventLayout.nextFreeSlot(on: day, from: 7 * 60 + 5, events: events, calendar: cal), 7 * 60 + 15)
        XCTAssertEqual(EventLayout.nextFreeSlot(on: day, from: 8 * 60, duration: 60, events: events, calendar: cal), 8 * 60)
        XCTAssertEqual(EventLayout.nextFreeSlot(on: day, from: 8.5 * 60, duration: 60, events: events, calendar: cal), 11.5 * 60, "8:30-9:30 would touch the 9:00 block")
    }
}

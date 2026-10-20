import XCTest
import CadenceCore

@MainActor
final class EventStoreTests: XCTestCase {
    final class FakeSource: EventSource, @unchecked Sendable {
        var calls: [(String, DateInterval)] = []
        var events: [String: [CalendarEvent]] = [:]
        func events(calendarId: String, range: DateInterval, force: Bool) async throws -> [CalendarEvent] {
            calls.append((calendarId, range))
            return (events[calendarId] ?? []).filter { $0.start < range.end && $0.end > range.start }
        }
    }

    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + Double(n) * 86_400) }
    private func event(_ id: String, _ d: Int, cal: String = "A") -> CalendarEvent {
        CalendarEvent(id: id, summary: id, start: day(d), end: day(d).addingTimeInterval(3600), calendarId: cal)
    }

    func testMissingRanges() {
        let covered = [DateInterval(start: day(2), end: day(4)), DateInterval(start: day(6), end: day(7))]
        let gaps = EventStore.missing(DateInterval(start: day(0), end: day(8)), covered: covered)
        XCTAssertEqual(gaps.map { [$0.start, $0.end] }, [[day(0), day(2)], [day(4), day(6)], [day(7), day(8)]])
        XCTAssertTrue(EventStore.missing(DateInterval(start: day(2), end: day(3)), covered: covered).isEmpty)
    }

    func testEnsureLoadedFetchesOnlyMissingAndNeverWipesOtherRanges() async {
        let src = FakeSource()
        src.events["A"] = [event("e1", 1), event("e5", 5)]
        let store = EventStore(source: src, cacheURL: nil)

        await store.ensureLoaded(range: DateInterval(start: day(0), end: day(3)), calendars: ["A"])
        await store.ensureLoaded(range: DateInterval(start: day(4), end: day(7)), calendars: ["A"])
        XCTAssertEqual(Set(store.events.map(\.id)), ["e1", "e5"], "loading a second range keeps the first")

        src.calls.removeAll()
        await store.ensureLoaded(range: DateInterval(start: day(1), end: day(2)), calendars: ["A"])
        XCTAssertTrue(src.calls.isEmpty, "already-loaded ranges aren't fetched again")

        await store.ensureLoaded(range: DateInterval(start: day(0), end: day(7)), calendars: ["A"])
        XCTAssertEqual(src.calls.count, 1, "only the gap between the two loaded ranges is fetched")
    }

    func testRefreshReplacesOnlyThatRange() async {
        let src = FakeSource()
        src.events["A"] = [event("old", 1), event("keep", 5)]
        let store = EventStore(source: src, cacheURL: nil)
        await store.ensureLoaded(range: DateInterval(start: day(0), end: day(7)), calendars: ["A"])
        src.events["A"] = [event("new", 1), event("keep", 5)]
        await store.refresh(range: DateInterval(start: day(0), end: day(3)), calendars: ["A"])
        XCTAssertEqual(Set(store.events.map(\.id)), ["new", "keep"])
    }

    func testOptimisticEditsAndCalendarMove() async {
        let store = EventStore(source: FakeSource(), cacheURL: nil)
        store.insert(event("x", 1))
        XCTAssertEqual(store.events.count, 1)
        let old = store.update(id: "x") { $0.calendarId = "B" }
        XCTAssertEqual(old?.calendarId, "A")
        XCTAssertEqual(store.events.first?.calendarId, "B")
        XCTAssertNotNil(store.remove(id: "x"))
        XCTAssertTrue(store.events.isEmpty)
    }

    func testRetainDropsUnlinkedCalendars() {
        let store = EventStore(source: FakeSource(), cacheURL: nil)
        store.insert(event("a", 1, cal: "A"))
        store.insert(event("b", 1, cal: "B"))
        store.retain(calendars: ["A"])
        XCTAssertEqual(store.events.map(\.id), ["a"])
    }
}

import XCTest
import CadenceCore

final class ICSTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let madrid = TimeZone(identifier: "Europe/Madrid")!

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, tz: TimeZone) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))!
    }

    private func cal(_ tz: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        c.firstWeekday = 2
        return c
    }

    private func range(_ a: Date, _ b: Date) -> DateInterval { DateInterval(start: a, end: b) }

    private func wrap(_ body: String) -> String {
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n\(body)END:VCALENDAR\r\n"
    }

    func testSingleUTCEventWithFoldedSummary() {
        let ics = wrap("""
        BEGIN:VEVENT\r
        UID:one@x\r
        DTSTART:20261021T080000Z\r
        DTEND:20261021T093000Z\r
        SUMMARY:Microeconomics\\, lecture with a very long title that needs to be fol\r
         ded over two lines\r
        END:VEVENT\r

        """)
        let r = range(date(2026, 10, 21, tz: utc), date(2026, 10, 22, tz: utc))
        let ev = ICSParser.parse(ics, calendarId: "c", range: r, calendar: cal(utc))
        XCTAssertEqual(ev.count, 1)
        XCTAssertEqual(ev[0].summary, "Microeconomics, lecture with a very long title that needs to be folded over two lines")
        XCTAssertEqual(ev[0].start, date(2026, 10, 21, 8, tz: utc))
        XCTAssertEqual(ev[0].end.timeIntervalSince(ev[0].start), 5400)
        XCTAssertEqual(ev[0].id, "one@x")
        XCTAssertFalse(ev[0].isAllDay)
    }

    func testRangeFiltering() {
        let ics = wrap("BEGIN:VEVENT\r\nUID:a\r\nDTSTART:20261021T080000Z\r\nDTEND:20261021T090000Z\r\nSUMMARY:A\r\nEND:VEVENT\r\n")
        let r = range(date(2026, 10, 22, tz: utc), date(2026, 10, 23, tz: utc))
        XCTAssertTrue(ICSParser.parse(ics, calendarId: "c", range: r, calendar: cal(utc)).isEmpty)
    }

    func testDurationInsteadOfDTEND() {
        let ics = wrap("BEGIN:VEVENT\r\nUID:d\r\nDTSTART:20261021T080000Z\r\nDURATION:PT1H30M\r\nSUMMARY:D\r\nEND:VEVENT\r\n")
        let r = range(date(2026, 10, 21, tz: utc), date(2026, 10, 22, tz: utc))
        let ev = ICSParser.parse(ics, calendarId: "c", range: r, calendar: cal(utc))
        XCTAssertEqual(ev.first?.end, date(2026, 10, 21, 9, 30, tz: utc))
    }

    func testZeroLengthIsDeadline() {
        let ics = wrap("BEGIN:VEVENT\r\nUID:dl\r\nDTSTART:20261021T215900Z\r\nDTEND:20261021T215900Z\r\nSUMMARY:Essay due\r\nEND:VEVENT\r\n")
        let r = range(date(2026, 10, 21, tz: utc), date(2026, 10, 22, tz: utc))
        let ev = ICSParser.parse(ics, calendarId: "c", range: r, calendar: cal(utc))
        XCTAssertEqual(ev.count, 1)
        XCTAssertTrue(ev[0].isDeadline)
        XCTAssertTrue(ev[0].isAllDayLike)
    }

    func testBlackboardOneSecondDeadlineIsDeadline() {
        // Blackboard exports some deadlines as start + 1 second; they must not become grid blocks.
        let ics = wrap("BEGIN:VEVENT\r\nUID:bb\r\nDTSTART:20261020T160000Z\r\nDTEND:20261020T160001Z\r\nSUMMARY:Deadline of Read document\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nUID:cls\r\nDTSTART:20261020T160000Z\r\nDTEND:20261020T172000Z\r\nSUMMARY:Class\r\nEND:VEVENT\r\n")
        let day = date(2026, 10, 20, tz: utc)
        let c = cal(utc)
        let ev = ICSParser.parse(ics, calendarId: "c", range: range(day, date(2026, 10, 21, tz: utc)), calendar: c)
        XCTAssertEqual(ev.count, 2)
        XCTAssertEqual(EventLayout.layout(ev, on: day, calendar: c).map(\.event.summary), ["Class"])
        XCTAssertEqual(EventLayout.allDayItems(ev, on: day, calendar: c).map(\.summary), ["Deadline of Read document"])
        XCTAssertEqual(EventLayout.layout(ev, on: day, calendar: c).first?.laneCount, 1)
    }

    func testWholeDayTimedEventGoesToAllDayStrip() {
        let ics = wrap("BEGIN:VEVENT\r\nUID:async\r\nDTSTART:20261020T000000Z\r\nDTEND:20261020T235900Z\r\nSUMMARY:Asynchronous\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nUID:cls\r\nDTSTART:20261020T150000Z\r\nDTEND:20261020T162000Z\r\nSUMMARY:Class\r\nEND:VEVENT\r\n")
        let day = date(2026, 10, 20, tz: utc)
        let c = cal(utc)
        let ev = ICSParser.parse(ics, calendarId: "c", range: range(day, date(2026, 10, 21, tz: utc)), calendar: c)
        XCTAssertEqual(EventLayout.allDayItems(ev, on: day, calendar: c).map(\.summary), ["Asynchronous"])
        let placed = EventLayout.layout(ev, on: day, calendar: c)
        XCTAssertEqual(placed.map(\.event.summary), ["Class"])
        XCTAssertEqual(placed.first?.laneCount, 1)
    }

    func testAllDayEvent() {
        let ics = wrap("BEGIN:VEVENT\r\nUID:ad\r\nDTSTART;VALUE=DATE:20261024\r\nDTEND;VALUE=DATE:20261026\r\nSUMMARY:Trip\r\nEND:VEVENT\r\n")
        let r = range(date(2026, 10, 24, tz: utc), date(2026, 10, 27, tz: utc))
        let c = cal(utc)
        let ev = ICSParser.parse(ics, calendarId: "c", range: r, calendar: c)
        XCTAssertEqual(ev.count, 1)
        XCTAssertTrue(ev[0].isAllDay)
        XCTAssertEqual(ev[0].start, date(2026, 10, 24, tz: utc))
        XCTAssertEqual(ev[0].end, date(2026, 10, 26, tz: utc))
    }

    func testWeeklyRecurrenceWithByDayCountAndExdate() {
        let ics = wrap("""
        BEGIN:VEVENT\r
        UID:wk\r
        DTSTART:20261005T100000Z\r
        DTEND:20261005T110000Z\r
        RRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=6\r
        EXDATE:20261012T100000Z\r
        SUMMARY:Seminar\r
        END:VEVENT\r

        """)
        let r = range(date(2026, 10, 1, tz: utc), date(2026, 12, 31, tz: utc))
        let ev = ICSParser.parse(ics, calendarId: "c", range: r, calendar: cal(utc))
        // 6 occurrences: Oct 5, 7, 12(excluded), 14, 19, 21  -> 5 shown
        let days = ev.map { cal(utc).component(.day, from: $0.start) }
        XCTAssertEqual(days, [5, 7, 14, 19, 21])
        XCTAssertEqual(Set(ev.map(\.id)).count, 5, "each instance needs a unique id")
    }

    func testUntilIsInclusive() {
        let ics = wrap("BEGIN:VEVENT\r\nUID:u\r\nDTSTART:20261005T100000Z\r\nDTEND:20261005T110000Z\r\nRRULE:FREQ=DAILY;UNTIL=20261007T100000Z\r\nSUMMARY:U\r\nEND:VEVENT\r\n")
        let r = range(date(2026, 10, 1, tz: utc), date(2026, 11, 1, tz: utc))
        XCTAssertEqual(ICSParser.parse(ics, calendarId: "c", range: r, calendar: cal(utc)).count, 3)
    }

    func testRecurrenceKeepsWallClockAcrossDST() {
        // Mondays 10:00 Madrid. Clocks go back on 2026-10-25, so UTC offset changes between Oct 19 and Oct 26.
        let ics = wrap("""
        BEGIN:VEVENT\r
        UID:dst\r
        DTSTART;TZID=Europe/Madrid:20261019T100000\r
        DTEND;TZID=Europe/Madrid:20261019T113000\r
        RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=3\r
        SUMMARY:Law\r
        END:VEVENT\r

        """)
        let r = range(date(2026, 10, 1, tz: utc), date(2026, 12, 1, tz: utc))
        let ev = ICSParser.parse(ics, calendarId: "c", range: r, calendar: cal(utc))
        XCTAssertEqual(ev.count, 3)
        XCTAssertEqual(ev[0].start, date(2026, 10, 19, 10, tz: madrid))
        XCTAssertEqual(ev[1].start, date(2026, 10, 26, 10, tz: madrid))
        XCTAssertNotEqual(ev[1].start.timeIntervalSince(ev[0].start), 7 * 86_400, "UTC offset shifts across the DST change")
        XCTAssertEqual(ev[1].end.timeIntervalSince(ev[1].start), 5400)
    }

    func testRecurrenceOverrideReplacesInstance() {
        let ics = wrap("""
        BEGIN:VEVENT\r
        UID:ov\r
        DTSTART:20261005T100000Z\r
        DTEND:20261005T110000Z\r
        RRULE:FREQ=DAILY;COUNT=3\r
        SUMMARY:Lab\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        UID:ov\r
        RECURRENCE-ID:20261006T100000Z\r
        DTSTART:20261006T140000Z\r
        DTEND:20261006T150000Z\r
        SUMMARY:Lab (moved)\r
        END:VEVENT\r

        """)
        let r = range(date(2026, 10, 1, tz: utc), date(2026, 11, 1, tz: utc))
        let ev = ICSParser.parse(ics, calendarId: "c", range: r, calendar: cal(utc))
        XCTAssertEqual(ev.count, 3)
        XCTAssertTrue(ev.contains { $0.summary == "Lab (moved)" && $0.start == date(2026, 10, 6, 14, tz: utc) })
        XCTAssertFalse(ev.contains { $0.summary == "Lab" && $0.start == date(2026, 10, 6, 10, tz: utc) })
    }

    func testMonthlyNthWeekday() {
        let ics = wrap("BEGIN:VEVENT\r\nUID:m\r\nDTSTART:20261012T100000Z\r\nDTEND:20261012T110000Z\r\nRRULE:FREQ=MONTHLY;BYDAY=2MO;COUNT=3\r\nSUMMARY:M\r\nEND:VEVENT\r\n")
        let r = range(date(2026, 10, 1, tz: utc), date(2027, 3, 1, tz: utc))
        let days = ICSParser.parse(ics, calendarId: "c", range: r, calendar: cal(utc)).map { cal(utc).dateComponents([.month, .day], from: $0.start) }
        XCTAssertEqual(days.map(\.day), [12, 9, 14])
        XCTAssertEqual(days.map(\.month), [10, 11, 12])
    }

    func testCancelledAndMalformedAreSkipped() {
        let ics = wrap("BEGIN:VEVENT\r\nUID:c\r\nDTSTART:20261021T080000Z\r\nDTEND:20261021T090000Z\r\nSTATUS:CANCELLED\r\nSUMMARY:X\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nUID:bad\r\nSUMMARY:no date\r\nEND:VEVENT\r\n")
        let r = range(date(2026, 10, 1, tz: utc), date(2026, 11, 1, tz: utc))
        XCTAssertTrue(ICSParser.parse(ics, calendarId: "c", range: r, calendar: cal(utc)).isEmpty)
    }

    func testEscapes() {
        let ics = wrap("BEGIN:VEVENT\r\nUID:e\r\nDTSTART:20261021T080000Z\r\nDTEND:20261021T090000Z\r\nSUMMARY:A\\;B\\, C\\\\n\r\nEND:VEVENT\r\n")
        let r = range(date(2026, 10, 21, tz: utc), date(2026, 10, 22, tz: utc))
        XCTAssertEqual(ICSParser.parse(ics, calendarId: "c", range: r, calendar: cal(utc)).first?.summary, "A;B, C\\n")
    }
}

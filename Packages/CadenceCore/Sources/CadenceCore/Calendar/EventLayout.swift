import Foundation

/// One timed event placed inside a single day column.
public struct PositionedEvent: Identifiable, Sendable {
    public let event: CalendarEvent
    /// Minutes from the start of the day, clipped to 0...1440.
    public let startMinute: Double
    public let endMinute: Double
    public let lane: Int
    public let laneCount: Int
    /// True when the event starts before this day / ends after it.
    public let clippedStart: Bool
    public let clippedEnd: Bool

    public var id: String { event.id }
    public var durationMinutes: Double { endMinute - startMinute }
}

/// Pure calendar geometry shared by the Mac grid and the iPhone timeline.
public enum EventLayout {
    /// Events shorter than this are laid out (and drawn) as if they were this long.
    public static let minimumMinutes: Double = 20
    public static let snapMinutes = 15

    // MARK: Splitting

    /// Events that belong in the all-day strip for `day`: all-day events and zero-length deadlines.
    public static func allDayItems(_ events: [CalendarEvent], on day: Date, calendar: Calendar = .current) -> [CalendarEvent] {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return [] }
        return events
            .filter { e in
                guard e.isAllDayLike else { return false }
                if e.isAllDay || e.spansWholeDay { return e.start < interval.end && e.end > interval.start }
                return e.start >= interval.start && e.start < interval.end
            }
            .sorted { ($0.isDeadline ? 1 : 0, $0.start, $0.summary) < ($1.isDeadline ? 1 : 0, $1.start, $1.summary) }
    }

    // MARK: Layout

    /// Places timed events in lanes. Only events that actually overlap (directly or through a chain) share width.
    public static func layout(_ events: [CalendarEvent], on day: Date, calendar: Calendar = .current) -> [PositionedEvent] {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return [] }
        struct Item { var event: CalendarEvent; var s: Double; var e: Double; var cs: Bool; var ce: Bool }

        let items: [Item] = events
            .filter { !$0.isAllDayLike && $0.start < interval.end && $0.end > interval.start }
            .map { ev in
                let s = minuteOfDay(ev.start, on: day, calendar: calendar)
                let e = minuteOfDay(ev.end, on: day, calendar: calendar)
                return Item(event: ev, s: s, e: max(e, min(1440, s + minimumMinutes)), cs: ev.start < interval.start, ce: ev.end > interval.end)
            }
            .sorted { ($0.s, -$0.e, $0.event.id) < ($1.s, -$1.e, $1.event.id) }

        var result: [PositionedEvent] = []
        var cluster: [(item: Item, lane: Int)] = []
        var laneEnds: [Double] = []
        var clusterEnd = -Double.infinity

        func flush() {
            let count = max(1, laneEnds.count)
            for (item, lane) in cluster {
                result.append(PositionedEvent(
                    event: item.event, startMinute: item.s, endMinute: item.e,
                    lane: lane, laneCount: count, clippedStart: item.cs, clippedEnd: item.ce
                ))
            }
            cluster = []
            laneEnds = []
            clusterEnd = -.infinity
        }

        for item in items {
            if item.s >= clusterEnd { flush() }
            let lane = laneEnds.firstIndex { $0 <= item.s } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(item.e) } else { laneEnds[lane] = item.e }
            cluster.append((item, lane))
            clusterEnd = max(clusterEnd, item.e)
        }
        flush()
        return result
    }

    // MARK: Minutes <-> dates

    /// Wall-clock minute of `date` within `day` (0 before the day, 1440 after it).
    public static func minuteOfDay(_ date: Date, on day: Date, calendar: Calendar = .current) -> Double {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return 0 }
        if date <= interval.start { return 0 }
        if date >= interval.end { return 1440 }
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) + Double(c.second ?? 0) / 60
    }

    /// The date at `minute` (0...1440) of `day`.
    public static func date(on day: Date, minute: Double, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        let m = Int(minute.rounded())
        if m >= 1440 { return calendar.date(byAdding: .day, value: 1, to: start) ?? start }
        return calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: start) ?? start
    }

    public static func snap(_ minutes: Double, step: Int = snapMinutes) -> Double {
        (minutes / Double(step)).rounded() * Double(step)
    }

    public static func snapDown(_ minutes: Double, step: Int = snapMinutes) -> Double {
        (minutes / Double(step)).rounded(.down) * Double(step)
    }

    // MARK: Free slots

    /// First start (on a 15-minute step, at or after `from`) where `duration` minutes fit without touching any timed event.
    public static func nextFreeSlot(
        on day: Date, from minute: Double, duration: Double = 60, events: [CalendarEvent], calendar: Calendar = .current
    ) -> Double {
        let busy = layout(events, on: day, calendar: calendar).map { ($0.startMinute, $0.endMinute) }
        var candidate = (minute / Double(snapMinutes)).rounded(.up) * Double(snapMinutes)
        while candidate + duration <= 1440 {
            if !busy.contains(where: { $0.0 < candidate + duration && $0.1 > candidate }) { return candidate }
            candidate += Double(snapMinutes)
        }
        return minute
    }
}

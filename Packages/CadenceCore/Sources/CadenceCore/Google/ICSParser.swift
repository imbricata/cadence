import Foundation

public enum ICSError: Error, LocalizedError {
    case http(Int)
    case notACalendar

    public var errorDescription: String? {
        switch self {
        case .http(let c): return "The calendar link returned an error (\(c))."
        case .notACalendar: return "That link doesn't look like a calendar feed."
        }
    }
}

/// Fetches an ICS feed (e.g. a Blackboard timetable link) and expands it into `CalendarEvent`s for a date range.
/// The raw feed is cached briefly so paging through days doesn't re-download it.
public actor ICSClient {
    private var cache: [URL: (text: String, fetched: Date)] = [:]

    public init() {}

    public func fetchEvents(url: URL, range: DateInterval, force: Bool = false, maxAge: TimeInterval = 300) async throws -> [CalendarEvent] {
        let text = try await feedText(url: url, force: force, maxAge: maxAge)
        return ICSParser.parse(text, calendarId: url.absoluteString, range: range)
    }

    private func feedText(url: URL, force: Bool, maxAge: TimeInterval) async throws -> String {
        if !force, let hit = cache[url], Date().timeIntervalSince(hit.fetched) < maxAge { return hit.text }
        var request = URLRequest(url: url)
        request.setValue("text/calendar", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw ICSError.http(http.statusCode) }
        let text = String(decoding: data, as: UTF8.self)
        guard text.contains("BEGIN:VCALENDAR") else { throw ICSError.notACalendar }
        cache[url] = (text, .now)
        return text
    }
}

/// Pure ICS parsing and recurrence expansion.
public enum ICSParser {

    // MARK: - Public

    public static func parse(_ text: String, calendarId: String, range: DateInterval, calendar: Calendar = .current) -> [CalendarEvent] {
        let raws = rawEvents(from: unfold(text))
        let masters = raws.filter { $0.recurrenceId == nil }
        let overrides = raws.filter { $0.recurrenceId != nil }

        // uid -> original start times that have an explicit override
        var overridden: [String: Set<Date>] = [:]
        for o in overrides {
            guard let uid = o.uid, let rid = o.recurrenceId, let d = rid.resolve(calendar: calendar) else { continue }
            overridden[uid, default: []].insert(d)
        }

        var events: [CalendarEvent] = []

        for raw in masters where !raw.cancelled {
            guard let dtstart = raw.dtstart, let start = dtstart.resolve(calendar: calendar) else { continue }
            let eventShape = shape(of: raw, start: start, calendar: calendar)

            guard let ruleText = raw.rrule, let rule = Rule(ruleText) else {
                let end = eventShape.end(for: start, calendar: calendar)
                if overlaps(start, end, range) {
                    events.append(makeEvent(raw, id: raw.uid ?? stableId(raw, start), start: start, end: end, calendarId: calendarId, isAllDay: dtstart.isDate))
                }
                continue
            }

            let ecal = dtstart.eventCalendar(base: calendar)
            let exdates = Set(raw.exdates.compactMap { $0.resolve(calendar: calendar) })
            let skip = overridden[raw.uid ?? ""] ?? []
            let uid = raw.uid ?? stableId(raw, start)

            for occ in rule.occurrences(from: start, isAllDay: dtstart.isDate, calendar: ecal, until: range.end) {
                if exdates.contains(occ) || skip.contains(occ) { continue }
                let end = eventShape.end(for: occ, calendar: ecal)
                guard overlaps(occ, end, range) else { continue }
                events.append(makeEvent(raw, id: "\(uid)#\(Int(occ.timeIntervalSince1970))", start: occ, end: end, calendarId: calendarId, isAllDay: dtstart.isDate))
            }
        }

        for o in overrides where !o.cancelled {
            guard let dtstart = o.dtstart, let start = dtstart.resolve(calendar: calendar),
                  let rid = o.recurrenceId, let ridDate = rid.resolve(calendar: calendar) else { continue }
            let end = shape(of: o, start: start, calendar: calendar).end(for: start, calendar: calendar)
            guard overlaps(start, end, range) else { continue }
            let uid = o.uid ?? stableId(o, start)
            events.append(makeEvent(o, id: "\(uid)#\(Int(ridDate.timeIntervalSince1970))", start: start, end: end, calendarId: calendarId, isAllDay: dtstart.isDate))
        }

        return events.sorted { $0.start < $1.start }
    }

    // MARK: - Raw events

    struct RawEvent {
        var uid: String?
        var summary = ""
        var dtstart: ICSDate?
        var dtend: ICSDate?
        var duration: TimeInterval?
        var rrule: String?
        var exdates: [ICSDate] = []
        var recurrenceId: ICSDate?
        var cancelled = false
    }

    struct ICSDate {
        var year: Int, month: Int, day: Int
        var hour = 0, minute = 0, second = 0
        var isDate: Bool
        var isUTC: Bool
        var tzid: String?

        var timeZone: TimeZone? {
            if isUTC { return TimeZone(identifier: "UTC") }
            guard let tzid else { return nil }
            return TimeZone(identifier: tzid) ?? TimeZone(identifier: windowsZones[tzid] ?? "")
        }

        /// Calendar in which this value's wall-clock arithmetic (recurrence) must happen.
        func eventCalendar(base: Calendar) -> Calendar {
            var c = base
            if !isDate, let tz = timeZone { c.timeZone = tz }
            return c
        }

        func resolve(calendar: Calendar) -> Date? {
            var c = eventCalendar(base: calendar)
            if isDate { c.timeZone = calendar.timeZone }
            var comps = DateComponents(year: year, month: month, day: day)
            if !isDate { comps.hour = hour; comps.minute = minute; comps.second = second }
            return c.date(from: comps)
        }
    }

    /// How an event's end is derived from any start (so recurring instances keep their length).
    struct Shape {
        var allDayDays: Int?      // for all-day events
        var seconds: TimeInterval // for timed events (0 = deadline)

        func end(for start: Date, calendar: Calendar = .current) -> Date {
            if let days = allDayDays { return calendar.date(byAdding: .day, value: days, to: start) ?? start.addingTimeInterval(86_400) }
            return start.addingTimeInterval(seconds)
        }
    }

    static func shape(of raw: RawEvent, start: Date, calendar: Calendar) -> Shape {
        let isAllDay = raw.dtstart?.isDate ?? false
        if isAllDay {
            if let e = raw.dtend?.resolve(calendar: calendar) {
                let days = calendar.dateComponents([.day], from: start, to: e).day ?? 1
                return Shape(allDayDays: max(1, days), seconds: 0)
            }
            if let d = raw.duration { return Shape(allDayDays: max(1, Int((d / 86_400).rounded())), seconds: 0) }
            return Shape(allDayDays: 1, seconds: 0)
        }
        if let e = raw.dtend?.resolve(calendar: calendar) { return Shape(allDayDays: nil, seconds: max(0, e.timeIntervalSince(start))) }
        if let d = raw.duration { return Shape(allDayDays: nil, seconds: max(0, d)) }
        return Shape(allDayDays: nil, seconds: 0)
    }

    static func makeEvent(_ raw: RawEvent, id: String, start: Date, end: Date, calendarId: String, isAllDay: Bool) -> CalendarEvent {
        CalendarEvent(id: id, summary: raw.summary, start: start, end: end, calendarId: calendarId, isAllDay: isAllDay, isCadenceBlock: false)
    }

    static func overlaps(_ start: Date, _ end: Date, _ range: DateInterval) -> Bool {
        if end > start { return start < range.end && end > range.start }
        return start >= range.start && start < range.end
    }

    /// Stable (not per-process) id for events with no UID.
    static func stableId(_ raw: RawEvent, _ start: Date) -> String {
        var h: UInt64 = 14_695_981_039_346_656_037
        for b in "\(raw.summary)|\(Int(start.timeIntervalSince1970))".utf8 { h = (h ^ UInt64(b)) &* 1_099_511_628_211 }
        return "ics-\(String(h, radix: 16))"
    }

    // MARK: - Line parsing

    static func rawEvents(from lines: [String]) -> [RawEvent] {
        var result: [RawEvent] = []
        var current: RawEvent?
        for line in lines {
            let upper = line.uppercased()
            if upper == "BEGIN:VEVENT" { current = RawEvent(); continue }
            if upper == "END:VEVENT" { if let c = current { result.append(c) }; current = nil; continue }
            guard current != nil else { continue }
            let prop = splitProperty(line)
            switch prop.name {
            case "UID": current?.uid = prop.value
            case "SUMMARY": current?.summary = unescape(prop.value)
            case "DTSTART": current?.dtstart = parseDate(prop.value, params: prop.params)
            case "DTEND": current?.dtend = parseDate(prop.value, params: prop.params)
            case "DURATION": current?.duration = parseDuration(prop.value)
            case "RRULE": current?.rrule = prop.value
            case "EXDATE":
                for part in prop.value.split(separator: ",") {
                    if let d = parseDate(String(part), params: prop.params) { current?.exdates.append(d) }
                }
            case "RECURRENCE-ID": current?.recurrenceId = parseDate(prop.value, params: prop.params)
            case "STATUS": if prop.value.uppercased() == "CANCELLED" { current?.cancelled = true }
            default: break
            }
        }
        return result
    }

    static func unfold(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var out: [String] = []
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = line.first, first == " " || first == "\t", !out.isEmpty {
                out[out.count - 1] += line.dropFirst()
            } else {
                out.append(String(line))
            }
        }
        return out
    }

    /// `NAME;PARAM=value;PARAM="quoted:value":VALUE` — colons inside quotes don't end the head.
    static func splitProperty(_ line: String) -> (name: String, params: [String: String], value: String) {
        var inQuotes = false
        var colon: String.Index?
        for i in line.indices {
            let ch = line[i]
            if ch == "\"" { inQuotes.toggle() }
            else if ch == ":" && !inQuotes { colon = i; break }
        }
        guard let colon else { return ("", [:], "") }
        let head = String(line[..<colon])
        let value = String(line[line.index(after: colon)...])

        var parts: [String] = []
        var buf = ""
        inQuotes = false
        for ch in head {
            if ch == "\"" { inQuotes.toggle(); continue }
            if ch == ";" && !inQuotes { parts.append(buf); buf = "" } else { buf.append(ch) }
        }
        parts.append(buf)

        var params: [String: String] = [:]
        for p in parts.dropFirst() {
            if let eq = p.firstIndex(of: "=") {
                params[String(p[..<eq]).uppercased()] = String(p[p.index(after: eq)...])
            }
        }
        return ((parts.first ?? "").uppercased(), params, value)
    }

    static func parseDate(_ value: String, params: [String: String]) -> ICSDate? {
        var s = value.trimmingCharacters(in: .whitespaces)
        var isUTC = false
        if s.hasSuffix("Z") || s.hasSuffix("z") { isUTC = true; s.removeLast() }
        let digits = s.filter { $0 != "T" && $0 != "t" }
        guard digits.allSatisfy(\.isNumber) else { return nil }
        func int(_ range: Range<Int>) -> Int {
            let chars = Array(digits)
            guard range.upperBound <= chars.count else { return 0 }
            return Int(String(chars[range])) ?? 0
        }
        if digits.count == 8 {
            return ICSDate(year: int(0..<4), month: int(4..<6), day: int(6..<8), isDate: true, isUTC: false, tzid: nil)
        }
        guard digits.count >= 14 else { return nil }
        let isDate = params["VALUE"]?.uppercased() == "DATE"
        return ICSDate(
            year: int(0..<4), month: int(4..<6), day: int(6..<8),
            hour: int(8..<10), minute: int(10..<12), second: int(12..<14),
            isDate: isDate, isUTC: isUTC, tzid: params["TZID"]
        )
    }

    /// RFC 5545 DURATION, e.g. PT1H30M, P1D, P2W.
    static func parseDuration(_ value: String) -> TimeInterval? {
        var s = value.trimmingCharacters(in: .whitespaces)
        var sign = 1.0
        if s.hasPrefix("-") { sign = -1; s.removeFirst() } else if s.hasPrefix("+") { s.removeFirst() }
        guard s.hasPrefix("P") else { return nil }
        s.removeFirst()
        var total = 0.0
        var number = ""
        var inTime = false
        for ch in s {
            if ch == "T" { inTime = true; continue }
            if ch.isNumber { number.append(ch); continue }
            guard let n = Double(number) else { return nil }
            number = ""
            switch ch {
            case "W": total += n * 604_800
            case "D": total += n * 86_400
            case "H" where inTime: total += n * 3_600
            case "M" where inTime: total += n * 60
            case "S" where inTime: total += n
            default: return nil
            }
        }
        return sign * total
    }

    /// Single left-to-right pass so `\\n` is a backslash followed by "n", not a newline.
    static func unescape(_ s: String) -> String {
        var out = ""
        var escaping = false
        for ch in s {
            if escaping {
                switch ch {
                case "n", "N": out.append("\n")
                default: out.append(ch)
                }
                escaping = false
            } else if ch == "\\" {
                escaping = true
            } else {
                out.append(ch)
            }
        }
        return out
    }

    static let windowsZones: [String: String] = [
        "W. Europe Standard Time": "Europe/Berlin",
        "Central Europe Standard Time": "Europe/Budapest",
        "Romance Standard Time": "Europe/Paris",
        "GMT Standard Time": "Europe/London",
        "E. Europe Standard Time": "Europe/Bucharest",
        "Eastern Standard Time": "America/New_York",
        "Central Standard Time": "America/Chicago",
        "Mountain Standard Time": "America/Denver",
        "Pacific Standard Time": "America/Los_Angeles",
        "UTC": "UTC"
    ]

    // MARK: - Recurrence

    struct Rule {
        enum Freq { case daily, weekly, monthly, yearly }
        var freq: Freq
        var interval = 1
        var count: Int?
        var until: ICSDate?
        var byDay: [(ordinal: Int?, weekday: Int)] = []
        var byMonthDay: [Int] = []
        var byMonth: [Int] = []
        var weekStart = 2 // Monday (Calendar weekday numbering: 1 = Sunday)

        init?(_ text: String) {
            var f: Freq?
            for part in text.split(separator: ";") {
                let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
                guard kv.count == 2 else { continue }
                let value = kv[1]
                switch kv[0].uppercased() {
                case "FREQ":
                    switch value.uppercased() {
                    case "DAILY": f = .daily
                    case "WEEKLY": f = .weekly
                    case "MONTHLY": f = .monthly
                    case "YEARLY": f = .yearly
                    default: return nil
                    }
                case "INTERVAL": interval = max(1, Int(value) ?? 1)
                case "COUNT": count = Int(value)
                case "UNTIL": until = ICSParser.parseDate(value, params: [:])
                case "BYDAY": byDay = value.split(separator: ",").compactMap { Self.parseByDay(String($0)) }
                case "BYMONTHDAY": byMonthDay = value.split(separator: ",").compactMap { Int($0) }
                case "BYMONTH": byMonth = value.split(separator: ",").compactMap { Int($0) }
                case "WKST": weekStart = Self.weekdayNumber(value) ?? 2
                default: break
                }
            }
            guard let f else { return nil }
            freq = f
        }

        static func weekdayNumber(_ code: String) -> Int? {
            ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7][code.uppercased()]
        }

        static func parseByDay(_ s: String) -> (ordinal: Int?, weekday: Int)? {
            guard s.count >= 2 else { return nil }
            let code = String(s.suffix(2))
            guard let wd = weekdayNumber(code) else { return nil }
            let prefix = String(s.dropLast(2))
            return (prefix.isEmpty ? nil : Int(prefix), wd)
        }

        /// All occurrence starts (including ones before the visible range, so COUNT is right), ending at `until`.
        func occurrences(from start: Date, isAllDay: Bool, calendar cal: Calendar, until limit: Date) -> [Date] {
            var cal = cal
            cal.firstWeekday = weekStart
            let untilDate: Date? = until.flatMap { u in
                guard let d = u.resolve(calendar: cal) else { return nil }
                return u.isDate ? (cal.date(byAdding: .day, value: 1, to: d)?.addingTimeInterval(-1)) : d
            }

            let startParts = cal.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: start)
            func at(day: Date) -> Date? {
                let d = cal.dateComponents([.year, .month, .day], from: day)
                var c = DateComponents(year: d.year, month: d.month, day: d.day)
                if !isAllDay { c.hour = startParts.hour; c.minute = startParts.minute; c.second = startParts.second }
                return cal.date(from: c)
            }

            var result: [Date] = []
            var generated = 0
            var done = false

            func emit(_ candidates: [Date]) {
                for c in candidates.sorted() where c >= start {
                    if let untilDate, c > untilDate { done = true; return }
                    if c > limit { done = true; return }
                    generated += 1
                    result.append(c)
                    if let count, generated >= count { done = true; return }
                }
            }

            let maxPeriods = 6_000
            var k = 0
            let startDay = cal.startOfDay(for: start)

            switch freq {
            case .daily:
                while !done && k < maxPeriods {
                    if let day = cal.date(byAdding: .day, value: k * interval, to: startDay), let c = at(day: day) {
                        let wd = cal.component(.weekday, from: c)
                        let monthOK = byMonth.isEmpty || byMonth.contains(cal.component(.month, from: c))
                        let dayOK = byDay.isEmpty || byDay.contains { $0.weekday == wd }
                        if monthOK && dayOK { emit([c]) }
                        if c > limit { done = true }
                    } else { done = true }
                    k += 1
                }
            case .weekly:
                let weekBase = cal.dateInterval(of: .weekOfYear, for: startDay)?.start ?? startDay
                let weekdays = byDay.isEmpty ? [startParts.weekday ?? 2] : byDay.map(\.weekday)
                while !done && k < maxPeriods {
                    guard let base = cal.date(byAdding: .weekOfYear, value: k * interval, to: weekBase) else { break }
                    if base > limit { break }
                    var cands: [Date] = []
                    for wd in weekdays {
                        let offset = (wd - weekStart + 7) % 7
                        if let day = cal.date(byAdding: .day, value: offset, to: base), let c = at(day: day) { cands.append(c) }
                    }
                    emit(cands)
                    k += 1
                }
            case .monthly, .yearly:
                let firstOfMonth = cal.date(from: DateComponents(year: startParts.year, month: startParts.month, day: 1)) ?? startDay
                let step: Calendar.Component = freq == .monthly ? .month : .year
                while !done && k < maxPeriods {
                    guard let base = cal.date(byAdding: step, value: k * interval, to: firstOfMonth) else { break }
                    if base > limit { break }
                    var cands: [Date] = []
                    let months: [Int] = freq == .yearly ? (byMonth.isEmpty ? [startParts.month ?? 1] : byMonth) : [cal.component(.month, from: base)]
                    for m in months {
                        let year = cal.component(.year, from: base)
                        guard let monthStart = cal.date(from: DateComponents(year: year, month: m, day: 1)) else { continue }
                        if freq == .monthly, !byMonth.isEmpty, !byMonth.contains(m) { continue }
                        cands.append(contentsOf: days(inMonthStarting: monthStart, cal: cal, defaultDay: startParts.day ?? 1, startWeekday: startParts.weekday ?? 2).compactMap(at(day:)))
                    }
                    emit(cands)
                    k += 1
                }
            }
            return result
        }

        private func days(inMonthStarting monthStart: Date, cal: Calendar, defaultDay: Int, startWeekday: Int) -> [Date] {
            let range = cal.range(of: .day, in: .month, for: monthStart) ?? 1..<29
            let dayCount = range.count
            func date(_ d: Int) -> Date? { cal.date(byAdding: .day, value: d - 1, to: monthStart) }

            if !byMonthDay.isEmpty {
                return byMonthDay.compactMap { d in
                    let n = d > 0 ? d : dayCount + d + 1
                    return (1...dayCount).contains(n) ? date(n) : nil
                }
            }
            if !byDay.isEmpty {
                var out: [Date] = []
                for rule in byDay {
                    let matching = (1...dayCount).compactMap(date).filter { cal.component(.weekday, from: $0) == rule.weekday }
                    if let n = rule.ordinal {
                        let idx = n > 0 ? n - 1 : matching.count + n
                        if matching.indices.contains(idx) { out.append(matching[idx]) }
                    } else {
                        out.append(contentsOf: matching)
                    }
                }
                return out
            }
            return defaultDay <= dayCount ? [date(defaultDay)].compactMap { $0 } : []
        }
    }
}

import Foundation

/// Fetches and parses a plain ICS calendar feed (e.g. a Blackboard timetable link)
/// into `CalendarEvent`s, so subscribed feeds can be shown without the Google Calendar API.
public struct ICSClient: Sendable {
    public init() {}

    public func fetchEvents(url: URL) async throws -> [CalendarEvent] {
        var request = URLRequest(url: url)
        request.setValue("text/calendar", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        let text = String(decoding: data, as: UTF8.self)
        return Self.parse(text, calendarId: url.absoluteString)
    }

    public static func parse(_ text: String, calendarId: String) -> [CalendarEvent] {
        let lines = unfold(text)
        var events: [CalendarEvent] = []
        var i = 0
        while i < lines.count {
            if lines[i].uppercased() == "BEGIN:VEVENT" {
                var dtstart: String?
                var dtend: String?
                var tzid: String?
                var summary = ""
                var uid: String?
                i += 1
                while i < lines.count, lines[i].uppercased() != "END:VEVENT" {
                    let (name, params, value) = splitProperty(lines[i])
                    switch name {
                    case "DTSTART":
                        dtstart = value
                        tzid = params.first { $0.hasPrefix("TZID=") }.map { String($0.dropFirst(5)) }
                    case "DTEND": dtend = value
                    case "SUMMARY": summary = value
                    case "UID": uid = value
                    default: break
                    }
                    i += 1
                }
                if let startStr = dtstart, let endStr = dtend,
                   let s = parseDate(startStr, tzid: tzid),
                   let e = parseDate(endStr, tzid: tzid) {
                    let id = uid ?? "ics-\(s.timeIntervalSince1970)-\(abs(summary.hashValue))"
                    events.append(CalendarEvent(
                        id: id,
                        summary: unescape(summary),
                        start: s, end: e,
                        calendarId: calendarId,
                        isAllDay: startStr.trimmingCharacters(in: .whitespaces).count <= 8,
                        isCadenceBlock: false
                    ))
                }
            }
            i += 1
        }
        return events
    }

    private static func splitProperty(_ line: String) -> (name: String, params: [String], value: String) {
        guard let colon = line.firstIndex(of: ":") else { return ("", [], "") }
        let head = String(line[..<colon])
        let value = String(line[line.index(after: colon)...])
        let parts = head.split(separator: ";")
        return (parts.first.map { String($0).uppercased() } ?? "", parts.dropFirst().map(String.init), value)
    }

    private static func parseDate(_ value: String, tzid: String?) -> Date? {
        var body = value.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }
        var isUTC = false
        if body.hasSuffix("Z") { isUTC = true; body.removeLast() }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = body.count == 8 ? "yyyyMMdd" : "yyyyMMdd'T'HHmmss"
        if isUTC { df.timeZone = TimeZone(identifier: "UTC") }
        else if let tzid { df.timeZone = TimeZone(identifier: tzid) ?? .current }
        else { df.timeZone = .current }
        return df.date(from: body)
    }

    private static func unfold(_ text: String) -> [String] {
        var out: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), var last = out.popLast() {
                out.append(last + String(line.dropFirst()))
            } else {
                out.append(line)
            }
        }
        return out
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
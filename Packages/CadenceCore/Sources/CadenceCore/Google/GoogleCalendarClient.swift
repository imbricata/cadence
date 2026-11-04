import Foundation

// MARK: - DTOs

public struct GoogleCalendar: Codable, Identifiable, Sendable {
    public var id: String
    public var summary: String?
    public var primary: Bool?
    public var backgroundColor: String?
    public var description: String?
}

public struct GoogleEvent: Codable, Identifiable, Sendable {
    public var id: String?
    public var summary: String?
    public var start: GoogleEventTime?
    public var end: GoogleEventTime?
    public var colorId: String?
    public var extendedProperties: GoogleExtendedProperties?
    public var status: String?
}

public struct GoogleEventTime: Codable, Sendable {
    public var dateTime: String?
    public var date: String?
    public var timeZone: String?
}

public struct GoogleExtendedProperties: Codable, Sendable {
    public var custom: [String: String]?
    public enum CodingKeys: String, CodingKey { case custom = "private" }
}

public struct GoogleCalendarList: Codable, Sendable {
    public var items: [GoogleCalendar]
}

public struct GoogleEventList: Codable, Sendable {
    public var items: [GoogleEvent]
    public var nextPageToken: String?

    public init(items: [GoogleEvent], nextPageToken: String? = nil) { self.items = items; self.nextPageToken = nextPageToken }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([GoogleEvent].self, forKey: .items) ?? []
        nextPageToken = try c.decodeIfPresent(String.self, forKey: .nextPageToken)
    }
}

/// A normalized event for display, tagged with its source calendar.
public struct CalendarEvent: Identifiable, Codable, Sendable {
    public var id: String
    public var summary: String
    public var start: Date
    public var end: Date
    public var calendarId: String
    public var isAllDay: Bool
    public var isCadenceBlock: Bool

    /// A timed event with no real length (e.g. an assignment due date). Shown as a marker, never as a block.
    /// Under a minute, not just zero: Blackboard exports some deadlines as start + 1 second.
    public var isDeadline: Bool { !isAllDay && end.timeIntervalSince(start) < 60 }
    /// A timed event that runs the whole day (e.g. "Asynchronous", 00:00-23:59). It would otherwise
    /// squeeze every other event of that day into a narrow lane.
    public var spansWholeDay: Bool { !isAllDay && end.timeIntervalSince(start) >= 23 * 3600 }
    /// Belongs in the all-day strip rather than the hour grid.
    public var isAllDayLike: Bool { isAllDay || isDeadline || spansWholeDay }

    public init(id: String, summary: String, start: Date, end: Date, calendarId: String, isAllDay: Bool = false, isCadenceBlock: Bool = false) {
        self.id = id; self.summary = summary; self.start = start; self.end = end
        self.calendarId = calendarId; self.isAllDay = isAllDay; self.isCadenceBlock = isCadenceBlock
    }
}

// MARK: - Client

public struct GoogleCalendarAPI: Sendable {
    public init() {}

    private static let base = "https://www.googleapis.com/calendar/v3"

    // MARK: Calendars

    public func listCalendars(accessToken: String) async throws -> [GoogleCalendar] {
        let data = try await request("/users/me/calendarList", token: accessToken)
        let list = try decode(GoogleCalendarList.self, data)
        return list.items
    }

    @discardableResult
    public func createCalendar(accessToken: String, name: String, description: String? = nil) async throws -> String {
        var body: [String: String] = ["summary": name]
        if let description { body["description"] = description }
        let data = try await request("/calendars", token: accessToken, method: "POST", body: try encode(body))
        struct Created: Decodable { let id: String }
        return try decode(Created.self, data).id
    }

    public func renameCalendar(accessToken: String, calendarId: String, name: String) async throws {
        let body: [String: String] = ["summary": name]
        _ = try await request("/calendars/\(Self.pathEscape(calendarId))", token: accessToken, method: "PATCH", body: try encode(body))
    }

    public func deleteCalendar(accessToken: String, calendarId: String) async throws {
        _ = try await request("/calendars/\(Self.pathEscape(calendarId))", token: accessToken, method: "DELETE")
    }

    public func setCalendarColor(accessToken: String, calendarId: String, hex: String) async throws {
        let fg = "000000"
        let body: [String: String] = [
            "backgroundColor": hex, "foregroundColor": fg
        ]
        _ = try await request("/users/me/calendarList/\(Self.pathEscape(calendarId))", token: accessToken, method: "PATCH", body: try encode(body))
    }

    // MARK: Events

    public func listEvents(accessToken: String, calendarId: String, start: Date, end: Date) async throws -> [GoogleEvent] {
        var all: [GoogleEvent] = []
        var pageToken: String?
        repeat {
            var query = [
                ("timeMin", GoogleDateFormat.format(start)),
                ("timeMax", GoogleDateFormat.format(end)),
                ("singleEvents", "true"),
                ("orderBy", "startTime"),
                ("maxResults", "2500"),
                ("timeZone", TimeZone.current.identifier),
                ("fields", "nextPageToken,items(id,summary,status,start,end,extendedProperties/private)")
            ]
            if let pageToken { query.append(("pageToken", pageToken)) }
            let data = try await request("/calendars/\(Self.pathEscape(calendarId))/events", token: accessToken, query: query)
            let page = try decode(GoogleEventList.self, data)
            all.append(contentsOf: page.items.filter { $0.status != "cancelled" })
            pageToken = page.nextPageToken
        } while pageToken != nil
        return all
    }

    /// Undo for delete: Google keeps a deleted event as `cancelled`, and PATCHing it back restores it.
    public func restoreEvent(accessToken: String, calendarId: String, eventId: String) async throws {
        let data = try JSONSerialization.data(withJSONObject: ["status": "confirmed"])
        _ = try await request("/calendars/\(Self.pathEscape(calendarId))/events/\(Self.pathEscape(eventId))", token: accessToken, method: "PATCH", body: data)
    }

    @discardableResult
    public func createEvent(accessToken: String, calendarId: String, summary: String, start: Date, end: Date) async throws -> GoogleEvent {
        let event = GoogleEvent(
            summary: summary,
            start: GoogleEventTime(dateTime: GoogleDateFormat.format(start), timeZone: TimeZone.current.identifier),
            end: GoogleEventTime(dateTime: GoogleDateFormat.format(end), timeZone: TimeZone.current.identifier),
            colorId: nil,
            extendedProperties: GoogleExtendedProperties(custom: ["cadence": "1"]),
            status: nil
        )
        let data = try await request("/calendars/\(Self.pathEscape(calendarId))/events", token: accessToken, method: "POST", body: try encode(event))
        return try decode(GoogleEvent.self, data)
    }

    public func updateEvent(accessToken: String, calendarId: String, eventId: String, summary: String? = nil, start: Date? = nil, end: Date? = nil) async throws {
        var body: [String: Any] = [:]
        if let summary { body["summary"] = summary }
        if let start { body["start"] = ["dateTime": GoogleDateFormat.format(start), "timeZone": TimeZone.current.identifier] }
        if let end { body["end"] = ["dateTime": GoogleDateFormat.format(end), "timeZone": TimeZone.current.identifier] }
        let data = try JSONSerialization.data(withJSONObject: body)
        _ = try await request("/calendars/\(Self.pathEscape(calendarId))/events/\(Self.pathEscape(eventId))", token: accessToken, method: "PATCH", body: data)
    }

    public func moveEvent(accessToken: String, fromCalendarId: String, toCalendarId: String, eventId: String) async throws {
        _ = try await request("/calendars/\(Self.pathEscape(fromCalendarId))/events/\(Self.pathEscape(eventId))/move", token: accessToken, method: "POST", query: [("destination", toCalendarId)])
    }

    public func deleteEvent(accessToken: String, calendarId: String, eventId: String) async throws {
        _ = try await request("/calendars/\(Self.pathEscape(calendarId))/events/\(Self.pathEscape(eventId))", token: accessToken, method: "DELETE")
    }

    // MARK: - Networking

    private func request(
        _ path: String, token: String, method: String = "GET",
        query: [(String, String)] = [], body: Data? = nil
    ) async throws -> Data {
        var comps = URLComponents(string: Self.base + path)!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        var request = URLRequest(url: comps.url!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GoogleAPIError.decoding("no response") }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw GoogleAPIError.unauthorized }
            let msg = Self.googleErrorMessage(data) ?? String(data: data, encoding: .utf8) ?? "unknown"
            throw GoogleAPIError.http(http.statusCode, msg)
        }
        return data
    }

    private static func googleErrorMessage(_ data: Data) -> String? {
        struct Body: Decodable { struct Inner: Decodable { let message: String }; let error: Inner }
        return (try? JSONDecoder().decode(Body.self, from: data))?.error.message
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw GoogleAPIError.decoding(String(describing: error)) }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    private static func pathEscape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
    }
}
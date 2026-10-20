import Foundation

/// Anything that can return the events of one calendar for a date range.
public protocol EventSource: Sendable {
    func events(calendarId: String, range: DateInterval, force: Bool) async throws -> [CalendarEvent]
}

public extension CalendarEvent {
    /// Normalizes a Google Calendar API event. Returns nil for events without usable times.
    init?(google e: GoogleEvent, calendarId: String) {
        guard let s = e.start?.dateTime.flatMap(GoogleDateFormat.parse) ?? e.start?.date.flatMap(Self.dateOnly),
              let en = e.end?.dateTime.flatMap(GoogleDateFormat.parse) ?? e.end?.date.flatMap(Self.dateOnly) else { return nil }
        self.init(
            id: e.id ?? UUID().uuidString,
            summary: e.summary ?? "",
            start: s, end: en,
            calendarId: calendarId,
            isAllDay: e.start?.date != nil,
            isCadenceBlock: e.extendedProperties?.custom?["cadence"] == "1"
        )
    }

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func dateOnly(_ s: String) -> Date? { dateOnlyFormatter.date(from: s) }
}

/// Routes ICS feed URLs to the ICS client and everything else to the Google Calendar API.
public struct CompositeEventSource: EventSource {
    private let auth: GoogleAuth
    private let api = GoogleCalendarAPI()
    private let ics = ICSClient()

    public init(auth: GoogleAuth) { self.auth = auth }

    public func events(calendarId: String, range: DateInterval, force: Bool) async throws -> [CalendarEvent] {
        if calendarId.hasPrefix("http"), let url = URL(string: calendarId) {
            return try await ics.fetchEvents(url: url, range: range, force: force)
        }
        let token = try await auth.accessToken()
        let list = try await api.listEvents(accessToken: token, calendarId: calendarId, start: range.start, end: range.end)
        return list.compactMap { CalendarEvent(google: $0, calendarId: calendarId) }
    }
}

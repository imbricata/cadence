import Foundation
import SwiftData
import Observation

@MainActor
@Observable
public final class GoogleService {
    public let auth: GoogleAuth
    public let calendar: GoogleCalendarAPI
    public let syncEngine: SyncEngine

    private let store: AppStore

    public var lastSyncAt: Date?
    public var needsReconnect: Bool = false
    public var isSyncing: Bool = false

    public private(set) var cachedEvents: [CalendarEvent] = []

    private let cacheURL: URL

    public init(store: AppStore) {
        self.store = store
        self.auth = GoogleAuth.shared
        self.calendar = GoogleCalendarAPI()
        self.syncEngine = SyncEngine()
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheURL = support.appendingPathComponent("Cadence").appendingPathComponent("events-cache.json")
        cachedEvents = Self.loadCache(url: cacheURL)
    }

    public var isAuthorized: Bool { auth.isAuthorized }

    public func signIn() async {
        do { try await auth.authorize(); needsReconnect = false }
        catch { needsReconnect = true }
    }

    public func signOut() {
        auth.signOut()
        cachedEvents = []
        needsReconnect = false
    }

    // MARK: - Sync

    public func syncNow() async {
        guard isAuthorized else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let summary = try await syncEngine.syncAll(auth: auth, store: store)
            lastSyncAt = summary.lastSyncAt
            needsReconnect = false
        } catch {
            if let g = error as? GoogleAPIError, g.isAuthError {
                needsReconnect = true
            } else if error is DriveAPIError {
                needsReconnect = true
            }
        }
    }

    // MARK: - Calendars

    public func listGoogleCalendars() async throws -> [GoogleCalendar] {
        let token = try await auth.accessToken()
        return try await calendar.listCalendars(accessToken: token)
    }

    /// Links the classes calendar and creates/updates the read-only "Classes" area.
    public func linkClassesCalendar(_ cal: GoogleCalendar) {
        if let existing = classesArea(in: store.context) {
            updateArea(store, existing, name: cal.summary ?? "Classes", calendarId: cal.id)
        } else {
            createArea(store, name: cal.summary ?? "Classes", colorHex: "#888C96", symbolName: "graduationcap", calendarId: cal.id, isClasses: true)
        }
    }

    /// If the area has no calendar yet, create a Google calendar named after it and link it.
    public func ensureCalendar(for area: Area) async {
        guard isAuthorized, area.googleCalendarId.isEmpty, !area.isClassesCalendar else { return }
        do {
            let token = try await auth.accessToken()
            let id = try await calendar.createCalendar(accessToken: token, name: area.name)
            updateArea(store, area, calendarId: id)
            try? await applyCalendarAppearance(accessToken: token, area: area)
        } catch { /* non-fatal; user can link later */ }
    }

    public func applyAreaAppearance(_ area: Area) async {
        guard isAuthorized, !area.googleCalendarId.isEmpty, !area.isClassesCalendar else { return }
        do {
            let token = try await auth.accessToken()
            try? await calendar.renameCalendar(accessToken: token, calendarId: area.googleCalendarId, name: area.name)
            try? await applyCalendarAppearance(accessToken: token, area: area)
        } catch { /* non-fatal */ }
    }

    private func applyCalendarAppearance(accessToken: String, area: Area) async throws {
        try await calendar.setCalendarColor(accessToken: accessToken, calendarId: area.googleCalendarId, hex: area.colorHex.replacingOccurrences(of: "#", with: ""))
    }

    // MARK: - Events

    public func refreshEvents(start: Date, end: Date) async {
        guard isAuthorized else { return }
        let active = visibleAreas(in: store.context).filter { !$0.googleCalendarId.isEmpty }
        var events: [CalendarEvent] = []
        do {
            let token = try await auth.accessToken()
            for area in active {
                let list = try await calendar.listEvents(accessToken: token, calendarId: area.googleCalendarId, start: start, end: end)
                for e in list {
                    guard let s = e.start?.dateTime.flatMap(GoogleDateFormat.parse) ?? (e.start?.date.flatMap { Self.dateOnly($0) }),
                          let en = e.end?.dateTime.flatMap(GoogleDateFormat.parse) ?? (e.end?.date.flatMap { Self.dateOnly($0) }) else { continue }
                    events.append(CalendarEvent(
                        id: e.id ?? UUID().uuidString,
                        summary: e.summary ?? "",
                        start: s, end: en,
                        calendarId: area.googleCalendarId,
                        isAllDay: e.start?.date != nil,
                        isCadenceBlock: e.extendedProperties?.custom?["cadence"] == "1"
                    ))
                }
            }
            cachedEvents = events
            saveCache()
            needsReconnect = false
        } catch {
            if let g = error as? GoogleAPIError, g.isAuthError { needsReconnect = true }
        }
    }

    public func events(on date: Date) -> [CalendarEvent] {
        let day = Calendar.current.dateInterval(of: .day, for: date)!
        return cachedEvents.filter { $0.start < day.end && $0.end > day.start }
    }

    private static func dateOnly(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    private func saveCache() {
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(cachedEvents) { try? data.write(to: cacheURL) }
    }

    private static func loadCache(url: URL) -> [CalendarEvent] {
        guard let data = try? Data(contentsOf: url), let events = try? JSONDecoder().decode([CalendarEvent].self, from: data) else { return [] }
        return events
    }
}
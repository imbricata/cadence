import Foundation
import SwiftData
import Observation

public enum ConnectionState: Sendable {
    case disconnected, needsReconnect, offline, connected
}

/// A short message for the UI (toast), optionally with one action such as Undo.
public struct UserMessage: Identifiable {
    public let id = UUID()
    public var text: String
    public var actionTitle: String?
    public var action: (@MainActor () -> Void)?

    public init(_ text: String, actionTitle: String? = nil, action: (@MainActor () -> Void)? = nil) {
        self.text = text
        self.actionTitle = actionTitle
        self.action = action
    }
}

@MainActor
@Observable
public final class GoogleService {
    public let auth: GoogleAuth
    public let calendar: GoogleCalendarAPI
    public let syncEngine: SyncEngine
    public let eventStore: EventStore

    private let store: AppStore
    private let isDemo: Bool

    // MARK: State

    public private(set) var lastSyncAt: Date? {
        didSet { UserDefaults.standard.set(lastSyncAt, forKey: Self.lastSyncKey) }
    }
    public private(set) var needsReconnect = false
    public private(set) var isOffline = false
    public private(set) var isSyncing = false
    /// Diagnostics only (Settings > Advanced). Never shown in the main UI.
    public private(set) var lastEventError: String?
    public private(set) var lastSyncError: String?
    public private(set) var accountEmail: String?
    /// Latest toast. The UI shows it and clears it.
    public var message: UserMessage?

    public var cachedEvents: [CalendarEvent] { eventStore.events }
    public var lastEventCount: Int { eventStore.events.count }
    public var isAuthorized: Bool { isDemo || auth.isAuthorized }

    public var connectionState: ConnectionState {
        if !isAuthorized { return .disconnected }
        if needsReconnect { return .needsReconnect }
        if isOffline { return .offline }
        return .connected
    }

    // MARK: Private

    private static let lastSyncKey = "cadence.lastSyncAt"
    private static let emailKey = "cadence.accountEmail"
    private var pendingSync = false
    private var debounceTask: Task<Void, Never>?
    private var periodicTask: Task<Void, Never>?
    private var requestedRange: DateInterval?

    public init(store: AppStore, eventSource: EventSource? = nil, isDemo: Bool = false) {
        self.store = store
        self.isDemo = isDemo
        let auth = isDemo ? GoogleAuth(loadFromKeychain: false) : GoogleAuth.shared
        self.auth = auth
        self.calendar = GoogleCalendarAPI()
        self.syncEngine = SyncEngine()

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Cadence")
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("events-cache.json")) // pre-overhaul cache
        self.eventStore = EventStore(
            source: eventSource ?? CompositeEventSource(auth: auth),
            cacheURL: isDemo ? nil : dir.appendingPathComponent("events-cache-v2.json")
        )

        if !isDemo {
            lastSyncAt = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
            accountEmail = UserDefaults.standard.string(forKey: Self.emailKey)
        } else {
            lastSyncAt = .now.addingTimeInterval(-120)
            accountEmail = "you@example.com"
        }
        store.onChange = { [weak self] in self?.scheduleSync() }
    }

    // MARK: - Sign in / out

    public func signIn() async {
        do {
            try await auth.authorize()
            needsReconnect = false
        } catch GoogleAuthError.cancelled {
            return
        } catch {
            lastSyncError = Self.describe(error)
            message = UserMessage("Couldn't connect to Google.")
            return
        }
        // Restore from Drive first so a second device gets its Areas (and their calendars) before creating anything.
        await syncNow()
        await repairCalendarLinks()
        await refreshAccount()
        await refreshVisible(force: true)
    }

    public func signOut() {
        auth.signOut()
        eventStore.removeAll()
        needsReconnect = false
        accountEmail = nil
        UserDefaults.standard.removeObject(forKey: Self.emailKey)
    }

    // MARK: - Lifecycle

    /// Call when the app becomes active / inactive. While active: sync + refresh now and every 5 minutes.
    public func setActive(_ active: Bool) {
        periodicTask?.cancel()
        periodicTask = nil
        guard active, !isDemo else { return }
        periodicTask = Task { [weak self] in
            var first = true
            while !Task.isCancelled {
                guard let self else { return }
                await self.syncNow()
                await self.refreshVisible(force: !first)
                if first { await self.ensureHistory(); first = false }
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    // MARK: - Sync

    public func syncNow() async {
        guard isAuthorized, !isDemo else { return }
        if isSyncing { pendingSync = true; return }
        isSyncing = true
        repeat {
            pendingSync = false
            do {
                let summary = try await syncEngine.syncAll(auth: auth, store: store)
                lastSyncAt = summary.lastSyncAt
                lastSyncError = nil
                needsReconnect = false
                isOffline = false
            } catch {
                classify(error)
                lastSyncError = Self.describe(error)
            }
        } while pendingSync
        isSyncing = false
    }

    /// Debounced sync ~5 s after local changes.
    private func scheduleSync() {
        guard isAuthorized, !isDemo, !isSyncing else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    // MARK: - Account & calendars

    public func listGoogleCalendars() async throws -> [GoogleCalendar] {
        let token = try await auth.accessToken()
        return try await calendar.listCalendars(accessToken: token)
    }

    public func refreshAccount() async {
        guard isAuthorized, !isDemo, let cals = try? await listGoogleCalendars() else { return }
        if let primary = cals.first(where: { $0.primary == true }) {
            accountEmail = primary.id
            UserDefaults.standard.set(primary.id, forKey: Self.emailKey)
        }
    }

    /// Links the classes calendar and creates/updates the read-only "Classes" area.
    public func linkClassesCalendar(_ cal: GoogleCalendar) {
        setClasses(name: cal.summary ?? "Classes", calendarId: cal.id)
    }

    /// Links the Classes area to a raw ICS feed URL (e.g. a Blackboard timetable link).
    public func linkClassesICS(_ urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        setClasses(name: "Classes", calendarId: trimmed)
    }

    private func setClasses(name: String, calendarId: String) {
        if let existing = classesArea(in: store.context) {
            updateArea(store, existing, name: name, calendarId: calendarId)
        } else {
            createArea(store, name: name, colorHex: "#888C96", symbolName: "graduationcap", calendarId: calendarId, isClasses: true)
        }
        Task { await refreshVisible(force: true) }
    }

    /// Validates an ICS link by downloading it. Returns the number of events found in the next ~year.
    public func validateICS(_ urlString: String) async throws -> Int {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme?.hasPrefix("http") == true else {
            throw ICSError.notACalendar
        }
        let range = DateInterval(start: Date().addingTimeInterval(-30 * 86_400), end: Date().addingTimeInterval(365 * 86_400))
        return try await ICSClient().fetchEvents(url: url, range: range, force: true).count
    }

    private static func areaTag(_ area: Area) -> String { "Cadence area \(area.id.uuidString)" }

    /// If the area has no calendar yet, link the one already tagged for it (never duplicate), else create one.
    public func ensureCalendar(for area: Area) async {
        guard isAuthorized, !isDemo, area.googleCalendarId.isEmpty, !area.isClassesCalendar else { return }
        do {
            let token = try await auth.accessToken()
            let existing = try await calendar.listCalendars(accessToken: token)
            if let match = existing.first(where: { $0.description == Self.areaTag(area) }) {
                updateArea(store, area, calendarId: match.id)
                return
            }
            let id = try await calendar.createCalendar(accessToken: token, name: area.name, description: Self.areaTag(area))
            updateArea(store, area, calendarId: id)
            try? await applyCalendarAppearance(accessToken: token, area: area)
        } catch {
            classify(error)
        }
    }

    /// Creates / re-links calendars for Areas that have none.
    public func repairCalendarLinks() async {
        for area in visibleAreas(in: store.context) where area.googleCalendarId.isEmpty && !area.isClassesCalendar {
            await ensureCalendar(for: area)
        }
    }

    /// Removes an Area. Optionally deletes its Google calendar too (default is to keep it).
    public func removeArea(_ area: Area, deleteCalendar: Bool) async {
        let calendarId = area.googleCalendarId
        deleteArea(store, area)
        guard deleteCalendar, !calendarId.isEmpty, !area.isClassesCalendar, isAuthorized, !isDemo else { return }
        do {
            let token = try await auth.accessToken()
            try await calendar.deleteCalendar(accessToken: token, calendarId: calendarId)
        } catch {
            classify(error)
            message = UserMessage("The area was deleted, but its Google calendar couldn't be.")
        }
    }

    /// Re-points an Area at another existing Google calendar.
    public func linkArea(_ area: Area, to cal: GoogleCalendar) {
        updateArea(store, area, calendarId: cal.id)
        Task { await refreshVisible(force: true) }
    }

    public func applyAreaAppearance(_ area: Area) async {
        guard isAuthorized, !isDemo, !area.googleCalendarId.isEmpty, !area.isClassesCalendar else { return }
        do {
            let token = try await auth.accessToken()
            try? await calendar.renameCalendar(accessToken: token, calendarId: area.googleCalendarId, name: area.name)
            try? await applyCalendarAppearance(accessToken: token, area: area)
        } catch { classify(error) }
    }

    private func applyCalendarAppearance(accessToken: String, area: Area) async throws {
        try await calendar.setCalendarColor(accessToken: accessToken, calendarId: area.googleCalendarId, hex: area.colorHex.replacingOccurrences(of: "#", with: ""))
    }

    // MARK: - Events

    /// Calendars that should be loaded: every visible Area (ICS feeds work without Google).
    private func activeCalendarIds() -> [String] {
        visibleAreas(in: store.context)
            .map(\.googleCalendarId)
            .filter { !$0.isEmpty && (isAuthorized || $0.hasPrefix("http")) }
    }

    /// Views call this with the range they show (±7 days of padding is added).
    public func ensureEvents(in range: DateInterval) async {
        let padded = DateInterval(start: range.start.addingTimeInterval(-7 * 86_400), end: range.end.addingTimeInterval(7 * 86_400))
        requestedRange = requestedRange.map { DateInterval(start: min($0.start, padded.start), end: max($0.end, padded.end)) } ?? padded
        let cals = activeCalendarIds()
        eventStore.retain(calendars: Set(cals))
        let failures = await eventStore.ensureLoaded(range: padded, calendars: cals)
        record(failures: failures, attempted: cals)
    }

    /// Re-downloads the ranges the app is showing (default: around today).
    public func refreshVisible(force: Bool = true) async {
        let base = DateInterval(start: .now.addingTimeInterval(-7 * 86_400), end: .now.addingTimeInterval(21 * 86_400))
        var range = base
        if let r = requestedRange { range = DateInterval(start: min(base.start, r.start), end: max(base.end, r.end)) }
        let cals = activeCalendarIds()
        eventStore.retain(calendars: Set(cals))
        let failures = await eventStore.refresh(range: range, calendars: cals)
        record(failures: failures, attempted: cals)
    }

    /// Eight weeks of history so Insights can chart follow-through.
    public func ensureHistory() async {
        await ensureEvents(in: DateInterval(start: .now.addingTimeInterval(-57 * 86_400), end: .now))
    }

    private func record(failures: [String: Error], attempted: [String]) {
        if failures.isEmpty {
            lastEventError = nil
            isOffline = false
            if attempted.contains(where: { !$0.hasPrefix("http") }) { needsReconnect = false }
            return
        }
        for (_, e) in failures { classify(e) }
        lastEventError = failures.map { "\(Self.describe($0.value))" }.joined(separator: "\n")
    }

    /// Maps an error onto connection state. Only a real auth failure asks for reconnection.
    private func classify(_ error: Error) {
        if isOfflineError(error) { isOffline = true; return }
        if let g = error as? GoogleAPIError, g.isAuthError { needsReconnect = true; return }
        if let a = error as? GoogleAuthError {
            switch a {
            case .invalidGrant, .notSignedIn: needsReconnect = true
            default: break
            }
            return
        }
        if let d = error as? DriveAPIError, d.isAuthError { needsReconnect = true }
    }

    private static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    // MARK: - Block operations (optimistic)

    @discardableResult
    public func createBlock(area: Area, start: Date, end: Date, summary: String? = nil) async -> CalendarEvent? {
        guard !area.googleCalendarId.isEmpty else {
            message = UserMessage("\(area.name) has no calendar yet. Connect Google first.")
            return nil
        }
        let temp = CalendarEvent(
            id: "local-\(UUID().uuidString)", summary: summary ?? area.name, start: start, end: end,
            calendarId: area.googleCalendarId, isAllDay: false, isCadenceBlock: true
        )
        eventStore.insert(temp)
        if isDemo { return temp }
        do {
            let token = try await auth.accessToken()
            let created = try await calendar.createEvent(accessToken: token, calendarId: area.googleCalendarId, summary: temp.summary, start: start, end: end)
            guard let real = CalendarEvent(google: created, calendarId: area.googleCalendarId) else {
                eventStore.remove(id: temp.id)
                return nil
            }
            eventStore.replace(id: temp.id, with: real)
            return real
        } catch {
            eventStore.remove(id: temp.id)
            classify(error)
            message = UserMessage("Couldn't create the block.")
            return nil
        }
    }

    public func updateBlock(event: CalendarEvent, start: Date?, end: Date?, summary: String?) async {
        let newStart = start ?? event.start
        let newEnd = end ?? event.end
        let old = eventStore.update(id: event.id) { e in
            e.start = newStart; e.end = newEnd
            if let summary { e.summary = summary }
        }
        let minutes = Int(newEnd.timeIntervalSince(newStart) / 60)
        if newStart != event.start || newEnd != event.end {
            rekeyBlockLog(store, googleEventId: event.id, oldStart: event.start, newStart: newStart, plannedMinutes: minutes)
        }
        guard !isDemo, !event.id.hasPrefix("local-") else { return }
        do {
            let token = try await auth.accessToken()
            try await calendar.updateEvent(accessToken: token, calendarId: event.calendarId, eventId: event.id, summary: summary, start: start, end: end)
        } catch {
            if let old {
                eventStore.replace(id: event.id, with: old)
                rekeyBlockLog(store, googleEventId: event.id, oldStart: newStart, newStart: old.start, plannedMinutes: Int(old.end.timeIntervalSince(old.start) / 60))
            }
            classify(error)
            message = UserMessage("Couldn't update the block.")
        }
    }

    /// Moves the block to another Area's calendar and re-tags its log.
    public func changeBlockArea(event: CalendarEvent, from oldArea: Area?, to area: Area) async {
        guard !area.googleCalendarId.isEmpty, area.googleCalendarId != event.calendarId else { return }
        let renames = oldArea.map { event.summary == $0.name } ?? false
        let newSummary = renames ? area.name : event.summary
        let old = eventStore.update(id: event.id) { e in e.calendarId = area.googleCalendarId; e.summary = newSummary }
        if let log = findBlockLog(store, googleEventId: event.id, eventStart: event.start) {
            log.areaId = area.id
            log.updatedAt = .now
            store.save()
        }
        guard !isDemo else { return }
        do {
            let token = try await auth.accessToken()
            try await calendar.moveEvent(accessToken: token, fromCalendarId: event.calendarId, toCalendarId: area.googleCalendarId, eventId: event.id)
            if renames {
                try? await calendar.updateEvent(accessToken: token, calendarId: area.googleCalendarId, eventId: event.id, summary: newSummary)
            }
        } catch {
            if let old { eventStore.replace(id: event.id, with: old) }
            if let log = findBlockLog(store, googleEventId: event.id, eventStart: event.start), let oldArea {
                log.areaId = oldArea.id
                log.updatedAt = .now
                store.save()
            }
            classify(error)
            message = UserMessage("Couldn't change the area.")
        }
    }

    public func deleteBlock(event: CalendarEvent) async {
        guard let removed = eventStore.remove(id: event.id) else { return }
        message = UserMessage("Block deleted", actionTitle: "Undo") { [weak self] in
            Task { await self?.restoreBlock(removed) }
        }
        guard !isDemo, !event.id.hasPrefix("local-") else { return }
        do {
            let token = try await auth.accessToken()
            try await calendar.deleteEvent(accessToken: token, calendarId: event.calendarId, eventId: event.id)
        } catch {
            eventStore.insert(removed)
            classify(error)
            message = UserMessage("Couldn't delete the block.")
        }
    }

    private func restoreBlock(_ event: CalendarEvent) async {
        eventStore.insert(event)
        guard !isDemo else { return }
        do {
            let token = try await auth.accessToken()
            try await calendar.restoreEvent(accessToken: token, calendarId: event.calendarId, eventId: event.id)
        } catch {
            eventStore.remove(id: event.id)
            classify(error)
            message = UserMessage("Couldn't restore the block.")
        }
    }

    public func events(on date: Date) -> [CalendarEvent] { eventStore.events(on: date) }
}

import Foundation
import Observation

/// Per-calendar event cache that remembers which date ranges it has loaded.
/// Views ask for the range they show; only missing ranges are fetched, and a refresh replaces events for
/// **that calendar and range only**, so screens can never wipe each other's data.
@MainActor
@Observable
public final class EventStore {
    public private(set) var events: [CalendarEvent] = []
    /// Bumped on every change (for insight recomputation).
    public private(set) var revision = 0

    @ObservationIgnored private var byCalendar: [String: [CalendarEvent]] = [:]
    @ObservationIgnored private var coverage: [String: [DateInterval]] = [:]
    @ObservationIgnored private var epoch: [String: Int] = [:]
    @ObservationIgnored private let source: EventSource
    @ObservationIgnored private let cacheURL: URL?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    public static let retention: TimeInterval = 60 * 24 * 3600

    public init(source: EventSource, cacheURL: URL?) {
        self.source = source
        self.cacheURL = cacheURL
        load()
    }

    // MARK: - Reading

    public func events(on day: Date) -> [CalendarEvent] {
        guard let interval = Calendar.current.dateInterval(of: .day, for: day) else { return [] }
        return events(overlapping: interval)
    }

    public func events(overlapping range: DateInterval) -> [CalendarEvent] {
        events.filter { e in
            e.end > e.start ? (e.start < range.end && e.end > range.start) : (e.start >= range.start && e.start < range.end)
        }
    }

    // MARK: - Loading

    /// Fetches whatever part of `range` hasn't been loaded yet. Returns per-calendar failures.
    @discardableResult
    public func ensureLoaded(range: DateInterval, calendars: [String]) async -> [String: Error] {
        var failures: [String: Error] = [:]
        for cal in calendars {
            for gap in Self.missing(range, covered: coverage[cal] ?? []) {
                do { try await fetch(calendarId: cal, range: gap, force: false) }
                catch { failures[cal] = error; break }
            }
        }
        return failures
    }

    /// Re-downloads `range` for the given calendars, replacing what was cached for exactly that span.
    @discardableResult
    public func refresh(range: DateInterval, calendars: [String]) async -> [String: Error] {
        var failures: [String: Error] = [:]
        for cal in calendars {
            do { try await fetch(calendarId: cal, range: range, force: true) }
            catch { failures[cal] = error }
        }
        return failures
    }

    private func fetch(calendarId: String, range: DateInterval, force: Bool) async throws {
        let startEpoch = epoch[calendarId, default: 0]
        let fetched = try await source.events(calendarId: calendarId, range: range, force: force)
        // A local edit landed while we were downloading: our snapshot may be stale, so drop it.
        guard epoch[calendarId, default: 0] == startEpoch else { return }
        var list = byCalendar[calendarId] ?? []
        list.removeAll { Self.overlaps($0, range) }
        list.append(contentsOf: fetched)
        byCalendar[calendarId] = list
        coverage[calendarId] = Self.merged((coverage[calendarId] ?? []) + [range])
        changed()
    }

    /// Forget calendars that are no longer linked to an Area.
    public func retain(calendars: Set<String>) {
        let stale = Set(byCalendar.keys).subtracting(calendars)
        guard !stale.isEmpty else { return }
        for k in stale { byCalendar[k] = nil; coverage[k] = nil }
        changed()
    }

    public func removeAll() {
        byCalendar = [:]
        coverage = [:]
        changed()
    }

    // MARK: - Optimistic local edits

    public func insert(_ event: CalendarEvent) {
        epoch[event.calendarId, default: 0] += 1
        byCalendar[event.calendarId, default: []].append(event)
        changed()
    }

    /// Replaces the event with `id` (in whichever calendar holds it) with `new`.
    @discardableResult
    public func replace(id: String, with new: CalendarEvent) -> CalendarEvent? {
        let old = remove(id: id, notify: false)
        epoch[new.calendarId, default: 0] += 1
        byCalendar[new.calendarId, default: []].append(new)
        changed()
        return old
    }

    @discardableResult
    public func remove(id: String) -> CalendarEvent? { remove(id: id, notify: true) }

    private func remove(id: String, notify: Bool) -> CalendarEvent? {
        for (cal, list) in byCalendar {
            if let idx = list.firstIndex(where: { $0.id == id }) {
                epoch[cal, default: 0] += 1
                let old = byCalendar[cal]?.remove(at: idx)
                if notify { changed() }
                return old
            }
        }
        return nil
    }

    /// Mutates an event in place and returns its previous value.
    @discardableResult
    public func update(id: String, _ mutate: (inout CalendarEvent) -> Void) -> CalendarEvent? {
        for (cal, list) in byCalendar {
            if let idx = list.firstIndex(where: { $0.id == id }) {
                let old = list[idx]
                var e = old
                mutate(&e)
                epoch[cal, default: 0] += 1
                byCalendar[cal]?[idx] = e
                if e.calendarId != cal {
                    byCalendar[cal]?.remove(at: idx)
                    epoch[e.calendarId, default: 0] += 1
                    byCalendar[e.calendarId, default: []].append(e)
                }
                changed()
                return old
            }
        }
        return nil
    }

    // MARK: - Internals

    private func changed() {
        prune()
        events = byCalendar.values.flatMap { $0 }.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        revision &+= 1
        scheduleSave()
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-Self.retention)
        for (cal, list) in byCalendar { byCalendar[cal] = list.filter { $0.end >= cutoff } }
        for (cal, ranges) in coverage {
            coverage[cal] = ranges.compactMap { r in
                r.end <= cutoff ? nil : DateInterval(start: max(r.start, cutoff), end: r.end)
            }
        }
    }

    static func overlaps(_ e: CalendarEvent, _ range: DateInterval) -> Bool {
        e.end > e.start ? (e.start < range.end && e.end > range.start) : (e.start >= range.start && e.start < range.end)
    }

    static func merged(_ ranges: [DateInterval]) -> [DateInterval] {
        let sorted = ranges.sorted { $0.start < $1.start }
        var out: [DateInterval] = []
        for r in sorted {
            if let last = out.last, r.start <= last.end {
                out[out.count - 1] = DateInterval(start: last.start, end: max(last.end, r.end))
            } else {
                out.append(r)
            }
        }
        return out
    }

    /// Parts of `range` not covered by `covered`.
    public static func missing(_ range: DateInterval, covered: [DateInterval]) -> [DateInterval] {
        var gaps: [DateInterval] = []
        var cursor = range.start
        for c in merged(covered) where c.end > range.start && c.start < range.end {
            if c.start > cursor { gaps.append(DateInterval(start: cursor, end: c.start)) }
            cursor = max(cursor, c.end)
        }
        if cursor < range.end { gaps.append(DateInterval(start: cursor, end: range.end)) }
        return gaps
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var events: [String: [CalendarEvent]]
        var coverage: [String: [[Double]]]
    }

    private func scheduleSave() {
        guard let cacheURL else { return }
        saveTask?.cancel()
        let snapshot = Snapshot(
            events: byCalendar,
            coverage: coverage.mapValues { $0.map { [$0.start.timeIntervalSince1970, $0.end.timeIntervalSince1970] } }
        )
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let data = try? JSONEncoder().encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    private func load() {
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        byCalendar = snap.events
        coverage = snap.coverage.mapValues { $0.compactMap { $0.count == 2 ? DateInterval(start: Date(timeIntervalSince1970: $0[0]), end: Date(timeIntervalSince1970: $0[1])) : nil } }
        prune()
        events = byCalendar.values.flatMap { $0 }.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }
}

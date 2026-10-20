import Foundation
import SwiftData

public struct AreaStat: Sendable {
    public var areaId: UUID
    public var rawMinutes: Int
    public var recentDaily: Double
    public var baselineDaily: Double
    public var referenceDaily: Double
    public var formPercent: Double?
    public var isCalibrating: Bool
    public var hasTarget: Bool
    public var daysObserved: Int
    public var targetWeeklyMinutes: Int?
}

public struct ActivityStat: Sendable {
    public var itemId: UUID
    public var rawMinutes: Int
    public var level: Int
}

public struct DayFollowThrough: Sendable {
    public var date: Date
    public var planned: Int
    public var loggedWeight: Double
}

public struct FollowThroughReport: Sendable {
    public var planned: Int
    public var loggedWeight: Double
    public var percent: Double?
    public var days: [DayFollowThrough]
}

public struct WeekFollowThrough: Sendable {
    public var weekStart: Date
    public var planned: Int
    public var loggedWeight: Double
    public var percent: Double?
}

public struct InsightSnapshot: Sendable {
    public var areas: [AreaStat]
    public var activities: [ActivityStat]
    public var followThrough: FollowThroughReport
    public var weeks: [WeekFollowThrough]

    public static let empty = InsightSnapshot(
        areas: [], activities: [],
        followThrough: FollowThroughReport(planned: 0, loggedWeight: 0, percent: nil, days: []),
        weeks: []
    )
}

private struct Contribution {
    var areaId: UUID
    var itemId: UUID?
    var date: Date
    var outcome: LogOutcome
    var minutes: Int

    var weighted: Double { easyWeightedMinutes(outcome: outcome, minutes: Double(minutes)) }
}

/// Everything that counts as time actually spent. Planned items, unlogged blocks and skipped entries are excluded.
private func workContributions(
    blockLogs: [BlockLog], entries: [BlockEntry], unplanned: [UnplannedLog]
) -> [Contribution] {
    var result: [Contribution] = []
    let logsByID = Dictionary(blockLogs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    var logsWithEntries = Set<UUID>()
    for entry in entries {
        guard let log = logsByID[entry.blockLogId] else { continue }
        logsWithEntries.insert(log.id)
        guard log.state != .unlogged, entry.outcome.countsAsWork, entry.minutes > 0 else { continue }
        result.append(Contribution(areaId: log.areaId, itemId: entry.itemId, date: log.eventStart, outcome: entry.outcome, minutes: entry.minutes))
    }
    for log in blockLogs where !logsWithEntries.contains(log.id) {
        guard log.state == .full || log.state == .easy, log.loggedMinutes > 0 else { continue }
        result.append(Contribution(areaId: log.areaId, itemId: nil, date: log.eventStart, outcome: LogOutcome(log.state), minutes: log.loggedMinutes))
    }
    for u in unplanned where u.outcome.countsAsWork && u.minutes > 0 {
        result.append(Contribution(areaId: u.areaId, itemId: u.itemId, date: u.date, outcome: u.outcome, minutes: u.minutes))
    }
    return result
}

public func computeInsights(context: ModelContext, events: [CalendarEvent], now: Date = .now) -> InsightSnapshot {
    let areas = allAreas(in: context)
    let items = allItems(in: context)
    let blockLogs = allBlockLogs(in: context)
    let entries = allBlockEntries(in: context)
    let unplanned = allUnplannedLogs(in: context)
    let targets = allTargets(in: context)

    let contributions = workContributions(blockLogs: blockLogs, entries: entries, unplanned: unplanned)

    // Areas (excluding classes)
    var areaStats: [AreaStat] = []
    let cal = Calendar.current
    let today = cal.startOfDay(for: now)
    for area in areas where !area.isClassesCalendar && !area.isArchived {
        let cs = contributions.filter { $0.areaId == area.id }
        let raw = cs.reduce(0) { $0 + $1.minutes }
        let daily: [Date: Double] = Dictionary(grouping: cs) { cal.startOfDay(for: $0.date) }
            .mapValues { $0.reduce(0) { $0 + $1.weighted } }

        let firstDate = cs.map(\.date).min() ?? area.createdAt
        let firstDay = cal.startOfDay(for: firstDate)
        // Today only counts once something is logged, so mornings don't drag form down.
        var lastDay = (daily[today] ?? 0) > 0 ? today : (cal.date(byAdding: .day, value: -1, to: today) ?? today)
        if lastDay < firstDay { lastDay = firstDay }
        let recent = denseExponentialAverage(daily: daily, firstDay: firstDay, lastDay: lastDay, halfLife: ScoringConfig.recentHalfLifeDays)
        let baseline = denseExponentialAverage(daily: daily, firstDay: firstDay, lastDay: lastDay, halfLife: ScoringConfig.baselineHalfLifeDays)

        let target = targets.first { $0.areaId == area.id && !$0.isDeleted }
        let hasTarget = target?.weeklyMinutes != nil
        var reference = baseline
        if let weekly = target?.weeklyMinutes { reference = Double(weekly) / 7 }

        let observed = daysObserved(firstDate: firstDate, now: now)
        let percent = formPercentage(recent: recent, reference: reference, daysObserved: observed, hasTarget: hasTarget)

        areaStats.append(AreaStat(
            areaId: area.id,
            rawMinutes: raw,
            recentDaily: recent,
            baselineDaily: baseline,
            referenceDaily: reference,
            formPercent: percent,
            isCalibrating: percent == nil,
            hasTarget: hasTarget,
            daysObserved: observed,
            targetWeeklyMinutes: target?.weeklyMinutes
        ))
    }

    // Activities (hours + levels)
    var activityMinutes: [UUID: Int] = [:]
    for c in contributions {
        if let id = c.itemId { activityMinutes[id, default: 0] += c.minutes }
    }
    let activityStats = items.filter { $0.kind == .activity }
        .map { item in
            ActivityStat(itemId: item.id, rawMinutes: activityMinutes[item.id] ?? 0, level: level(forHours: totalHours(minutes: activityMinutes[item.id] ?? 0)))
        }

    // Follow-through
    let areaCalendarIds = Set(areas.filter { !$0.isClassesCalendar && !$0.googleCalendarId.isEmpty }.map(\.googleCalendarId))
    let (report, weeks) = followThrough(areaCalendarIds: areaCalendarIds, blockLogs: blockLogs, events: events, now: now)

    return InsightSnapshot(areas: areaStats, activities: activityStats, followThrough: report, weeks: weeks)
}

// MARK: - Follow-through

private struct PlannedBlockRecord {
    var start: Date
    var weight: Double
}

/// One record per planned block that has already started: Area-calendar events plus logged blocks
/// that aren't (or are no longer) in the event cache. Planned blocks in the future never count.
private func plannedBlockRecords(
    areaCalendarIds: Set<String>, blockLogs: [BlockLog], events: [CalendarEvent], from: Date, now: Date
) -> [PlannedBlockRecord] {
    func key(_ id: String, _ start: Date) -> String { "\(id)|\(Int(start.timeIntervalSince1970))" }

    var weights: [String: Double] = [:]
    for log in blockLogs {
        let k = key(log.googleEventId, log.eventStart)
        weights[k] = max(weights[k] ?? 0, blockLogWeight(log.state))
    }

    var seen = Set<String>()
    var records: [PlannedBlockRecord] = []
    for e in events where areaCalendarIds.contains(e.calendarId) && !e.isAllDay && e.end > e.start && e.start >= from && e.start <= now {
        let k = key(e.id, e.start)
        guard seen.insert(k).inserted else { continue }
        records.append(PlannedBlockRecord(start: e.start, weight: weights[k] ?? 0))
    }
    // Logged blocks whose event isn't cached still count (they were planned).
    for log in blockLogs where log.state != .unlogged && log.eventStart >= from && log.eventStart <= now {
        let k = key(log.googleEventId, log.eventStart)
        guard seen.insert(k).inserted else { continue }
        records.append(PlannedBlockRecord(start: log.eventStart, weight: blockLogWeight(log.state)))
    }
    return records
}

private func followThrough(
    areaCalendarIds: Set<String>, blockLogs: [BlockLog], events: [CalendarEvent], now: Date
) -> (FollowThroughReport, [WeekFollowThrough]) {
    let cal = Calendar.current
    let weekCount = 8
    let thisWeekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)
    let firstWeekStart = cal.date(byAdding: .weekOfYear, value: -(weekCount - 1), to: thisWeekStart) ?? thisWeekStart
    let windowStart = cal.startOfDay(for: cal.date(byAdding: .day, value: -(ScoringConfig.followThroughWindowDays - 1), to: now) ?? now)

    let records = plannedBlockRecords(
        areaCalendarIds: areaCalendarIds, blockLogs: blockLogs, events: events,
        from: min(firstWeekStart, windowStart), now: now
    )

    let recent = records.filter { $0.start >= windowStart }
    let plannedCount = recent.count
    let weight = recent.reduce(0) { $0 + $1.weight }

    var days: [DayFollowThrough] = []
    for i in 0..<ScoringConfig.followThroughWindowDays {
        let day = cal.date(byAdding: .day, value: i, to: windowStart) ?? windowStart
        guard let interval = cal.dateInterval(of: .day, for: day) else { continue }
        let inDay = records.filter { interval.contains($0.start) }
        days.append(DayFollowThrough(date: day, planned: inDay.count, loggedWeight: inDay.reduce(0) { $0 + $1.weight }))
    }

    var weeks: [WeekFollowThrough] = []
    for i in 0..<weekCount {
        let start = cal.date(byAdding: .weekOfYear, value: i, to: firstWeekStart) ?? firstWeekStart
        let end = cal.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
        let inWeek = records.filter { $0.start >= start && $0.start < end }
        let w = inWeek.reduce(0) { $0 + $1.weight }
        weeks.append(WeekFollowThrough(weekStart: start, planned: inWeek.count, loggedWeight: w, percent: followThroughPercent(planned: inWeek.count, loggedWeight: w)))
    }

    let report = FollowThroughReport(
        planned: plannedCount, loggedWeight: weight,
        percent: followThroughPercent(planned: plannedCount, loggedWeight: weight), days: days
    )
    return (report, weeks)
}

/// Observed weekly minute totals (oldest first) for target proposals. Counts logged work only.
public func weeklyMinuteTotals(areaId: UUID, context: ModelContext, now: Date = .now) -> [Int] {
    let contributions = workContributions(
        blockLogs: allBlockLogs(in: context), entries: allBlockEntries(in: context), unplanned: allUnplannedLogs(in: context)
    ).filter { $0.areaId == areaId }

    let cal = Calendar.current
    var totals: [Date: Int] = [:]
    for c in contributions {
        let week = cal.dateInterval(of: .weekOfYear, for: c.date)?.start ?? c.date
        totals[week, default: 0] += c.minutes
    }
    return totals.keys.sorted().map { totals[$0] ?? 0 }
}

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

public struct InsightSnapshot: Sendable {
    public var areas: [AreaStat]
    public var activities: [ActivityStat]
    public var followThrough: FollowThroughReport
}

private struct Contribution {
    var areaId: UUID
    var itemId: UUID?
    var date: Date
    var outcome: LogOutcome
    var minutes: Int

    var weighted: Double { easyWeightedMinutes(outcome: outcome, minutes: Double(minutes)) }
}

public func computeInsights(context: ModelContext, events: [CalendarEvent], now: Date = .now) -> InsightSnapshot {
    let areas = allAreas(in: context)
    let items = allItems(in: context)
    let blockLogs = allBlockLogs(in: context)
    let entries = allBlockEntries(in: context)
    let unplanned = allUnplannedLogs(in: context)
    let targets = allTargets(in: context)

    var contributions: [Contribution] = []
    let logsByID = Dictionary(uniqueKeysWithValues: blockLogs.map { ($0.id, $0) })

    for entry in entries {
        guard let log = logsByID[entry.blockLogId] else { continue }
        contributions.append(Contribution(areaId: log.areaId, itemId: entry.itemId, date: log.eventStart, outcome: entry.outcome, minutes: entry.minutes))
    }
    for log in blockLogs {
        let hasEntries = entries.contains { $0.blockLogId == log.id }
        if !hasEntries, log.state == .full || log.state == .easy, log.loggedMinutes > 0 {
            let outcome: LogOutcome = log.state == .easy ? .easy : .full
            contributions.append(Contribution(areaId: log.areaId, itemId: nil, date: log.eventStart, outcome: outcome, minutes: log.loggedMinutes))
        }
    }
    for u in unplanned {
        contributions.append(Contribution(areaId: u.areaId, itemId: u.itemId, date: u.date, outcome: u.outcome, minutes: u.minutes))
    }

    // Areas (excluding classes)
    var areaStats: [AreaStat] = []
    let cal = Calendar.current
    for area in areas where !area.isClassesCalendar && !area.isArchived {
        let cs = contributions.filter { $0.areaId == area.id }
        let raw = cs.reduce(0) { $0 + $1.minutes }
        let daily: [Date: Double] = Dictionary(grouping: cs) { cal.startOfDay(for: $0.date) }
            .mapValues { $0.reduce(0) { $0 + $1.weighted } }
        let recent = ewDaily(daily, halfLife: ScoringConfig.recentHalfLifeDays, now: now)
        let baseline = ewDaily(daily, halfLife: ScoringConfig.baselineHalfLifeDays, now: now)

        let target = targets.first { $0.areaId == area.id && !$0.isDeleted }
        let hasTarget = target?.weeklyMinutes != nil
        var reference = baseline
        if let weekly = target?.weeklyMinutes { reference = Double(weekly) / 7 }

        let firstDate = cs.map(\.date).min() ?? area.createdAt
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
    let classIds = Set(areas.filter { $0.isClassesCalendar }.map(\.googleCalendarId))
    var activityMinutes: [UUID: Int] = [:]
    for c in contributions where c.itemId != nil {
        activityMinutes[c.itemId!, default: 0] += c.minutes
    }
    let activityStats = items.filter { $0.kind == .activity }
        .map { item in
            ActivityStat(itemId: item.id, rawMinutes: activityMinutes[item.id] ?? 0, level: level(forHours: totalHours(minutes: activityMinutes[item.id] ?? 0)))
        }

    // Follow-through (last 7 days)
    var ft = followThrough(context: context, areas: areas, blockLogs: blockLogs, events: events, classIds: classIds, now: now)

    ft.days.sort { $0.date < $1.date }

    return InsightSnapshot(areas: areaStats, activities: activityStats, followThrough: ft)
}

private func ewDaily(_ daily: [Date: Double], halfLife: Double, now: Date) -> Double {
    let entries = daily.map { (date: $0.key, value: $0.value) }
    let values = entries.map(\.value)
    let ages = entries.map { max(0, now.timeIntervalSince($0.date) / 86400) }
    return exponentiallyWeightedAverage(values: values, agesInDays: ages, halfLife: halfLife)
}

private func followThrough(context: ModelContext, areas: [Area], blockLogs: [BlockLog], events: [CalendarEvent], classIds: Set<String>, now: Date) -> FollowThroughReport {
    let cal = Calendar.current
    let windowStart = cal.startOfDay(for: cal.date(byAdding: .day, value: -6, to: now)!)

    let plannedEventIds = events
        .filter { !classIds.contains($0.calendarId) && $0.start >= windowStart && $0.start <= now }
        .map(\.id)
    var allPlanned = Set(plannedEventIds)
    for log in blockLogs where log.eventStart >= windowStart {
        allPlanned.insert(log.googleEventId)
    }

    var weights: [String: Double] = [:]
    for log in blockLogs where log.eventStart >= windowStart && log.eventStart <= now {
        let w = blockLogWeight(log.state)
        weights[log.googleEventId] = max(weights[log.googleEventId] ?? 0, w)
    }

    let plannedCount = allPlanned.count
    var loggedWeight = 0.0
    for id in allPlanned { loggedWeight += weights[id] ?? 0 }

    var days: [DayFollowThrough] = []
    for i in 0..<7 {
        let day = cal.date(byAdding: .day, value: i, to: windowStart)!
        let interval = cal.dateInterval(of: .day, for: day)!
        let planned = events.filter { !classIds.contains($0.calendarId) && interval.contains($0.start) }.count
        var w = 0.0
        for log in blockLogs where interval.contains(log.eventStart) {
            w = max(w, blockLogWeight(log.state))
        }
        days.append(DayFollowThrough(date: day, planned: planned, loggedWeight: w))
    }

    return FollowThroughReport(
        planned: plannedCount,
        loggedWeight: loggedWeight,
        percent: followThroughPercent(planned: plannedCount, loggedWeight: loggedWeight),
        days: days
    )
}

/// Observed weekly minute totals (newest last) for target proposals.
public func weeklyMinuteTotals(areaId: UUID, context: ModelContext, now: Date = .now) -> [Int] {
    let blockLogs = allBlockLogs(in: context)
    let entries = allBlockEntries(in: context)
    let unplanned = allUnplannedLogs(in: context)
    let logsByID = Dictionary(uniqueKeysWithValues: blockLogs.map { ($0.id, $0) })

    var totals: [String: Int] = [:]
    let cal = Calendar.current
    func weekKey(_ date: Date) -> String {
        let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(c.yearForWeekOfYear ?? 0)-\(c.weekOfYear ?? 0)"
    }
    for entry in entries {
        guard let log = logsByID[entry.blockLogId], log.areaId == areaId else { continue }
        totals[weekKey(log.eventStart), default: 0] += entry.minutes
    }
    for log in blockLogs where log.areaId == areaId {
        let hasEntries = entries.contains { $0.blockLogId == log.id }
        if !hasEntries { totals[weekKey(log.eventStart), default: 0] += log.loggedMinutes }
    }
    for u in unplanned where u.areaId == areaId {
        totals[weekKey(u.date), default: 0] += u.minutes
    }
    return totals.keys.sorted().map { totals[$0] ?? 0 }
}
import Foundation

public enum ScoringConfig {
    public static let recentHalfLifeDays: Double = 7
    public static let baselineHalfLifeDays: Double = 28
    public static let formCap: Double = 2.0
    public static let calibrationDays: Int = 14
    public static let easyWeight: Double = 0.75
    public static let followThroughWindowDays: Int = 7
    public static let targetProposalDays: Int = 21
    public static let levelHours: [Double] = [10, 25, 50, 100, 250, 500, 1000]
}

/// Minutes that count toward form. Only Full and Easy are work; Easy is weighted down.
/// Skipped and planned entries never count.
public func easyWeightedMinutes(outcome: LogOutcome, minutes: Double) -> Double {
    let base = max(0, minutes)
    switch outcome {
    case .full: return base
    case .easy: return base * ScoringConfig.easyWeight
    case .skipped, .planned: return 0
    }
}

/// Default logged minutes for one item in a block: Full = its share of the block,
/// Easy = half of that (rounded to 5), Skipped / planned = 0.
public func defaultEntryMinutes(outcome: LogOutcome, blockMinutes: Int, itemCount: Int) -> Int {
    let share = max(5, blockMinutes / max(1, itemCount))
    switch outcome {
    case .full: return share
    case .easy: return max(5, Int((Double(share) / 2 / 5).rounded()) * 5)
    case .skipped, .planned: return 0
    }
}

/// Default logged minutes for a whole block when it has no item entries.
public func defaultBlockMinutes(state: BlockLogState, plannedMinutes: Int) -> Int {
    switch state {
    case .full: return plannedMinutes
    case .easy: return max(5, Int((Double(plannedMinutes) / 2 / 5).rounded()) * 5)
    case .skipped, .unlogged: return 0
    }
}

/// Exponentially weighted average over a **dense** daily series: every calendar day from
/// `firstDay` to `lastDay` is included, with 0 for days that have no value.
public func denseExponentialAverage(
    daily: [Date: Double], firstDay: Date, lastDay: Date, halfLife: Double, calendar: Calendar = .current
) -> Double {
    let first = calendar.startOfDay(for: firstDay)
    let last = calendar.startOfDay(for: lastDay)
    guard last >= first else { return 0 }
    let count = (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1
    var values: [Double] = []
    var ages: [Double] = []
    values.reserveCapacity(count)
    ages.reserveCapacity(count)
    for i in 0..<count {
        let day = calendar.date(byAdding: .day, value: i, to: first) ?? first
        values.append(daily[day] ?? 0)
        ages.append(Double(count - 1 - i))
    }
    return exponentiallyWeightedAverage(values: values, agesInDays: ages, halfLife: halfLife)
}

/// Weighted average of daily values, weighted toward recent days.
/// `agesInDays` is how old each sample is (0 = today).
public func exponentiallyWeightedAverage(values: [Double], agesInDays: [Double], halfLife: Double) -> Double {
    guard values.count == agesInDays.count, !values.isEmpty else { return 0 }
    let weights = agesInDays.map { pow(0.5, max(0, $0) / halfLife) }
    let weightedSum = zip(values, weights).reduce(0.0) { $0 + ($1.0 * $1.1) }
    let weightSum = weights.reduce(0.0, +)
    return weightSum > 0 ? weightedSum / weightSum : 0
}

/// Form percentage. Returns nil while calibrating (first 14 days) unless a target is set.
public func formPercentage(recent: Double, reference: Double, daysObserved: Int, hasTarget: Bool) -> Double? {
    if !hasTarget && daysObserved < ScoringConfig.calibrationDays { return nil }
    guard reference > 0 else { return nil }
    let ratio = recent / reference
    return min(max(ratio, 0), ScoringConfig.formCap) * 100
}

/// 0-based level index (0 = under 10h, 1 = 10h+, ...). Levels at 10/25/50/100/250/500/1000 h.
public func level(forHours hours: Double) -> Int {
    guard hours > 0 else { return 0 }
    var lvl = 0
    for threshold in ScoringConfig.levelHours where hours >= threshold {
        lvl += 1
    }
    return lvl
}

public func levelLabel(hours: Double, levelIndex: Int) -> String {
    "Level \(levelIndex)"
}

/// Follow-through percent = weighted logged blocks / planned blocks, as a percentage.
public func followThroughPercent(planned: Int, loggedWeight: Double) -> Double? {
    guard planned > 0 else { return nil }
    return min(100.0, max(0, loggedWeight) / Double(planned) * 100)
}

/// Weighted score of a block's log: full = 1, easy = 0.75, else 0.
public func blockLogWeight(_ state: BlockLogState) -> Double {
    switch state {
    case .full: return 1.0
    case .easy: return 0.75
    case .unlogged, .skipped: return 0
    }
}

public func totalHours(minutes: Int) -> Double {
    Double(max(0, minutes)) / 60
}

/// Median of observed weekly minute totals (used for target proposals).
public func proposeTarget(weeklyMinutes: [Int]) -> Int? {
    let values = weeklyMinutes.filter { $0 >= 0 }
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let mid = sorted.count / 2
    if sorted.count % 2 == 0 {
        return (sorted[mid - 1] + sorted[mid]) / 2
    }
    return sorted[mid]
}

/// Whole days since the first observation (or the area's creation) for calibration.
public func daysObserved(firstDate: Date, now: Date = .now) -> Int {
    max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: firstDate), to: Calendar.current.startOfDay(for: now)).day ?? 0)
}
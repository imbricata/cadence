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

public func easyWeightedMinutes(outcome: LogOutcome, minutes: Double) -> Double {
    let base = max(0, minutes)
    return outcome == .easy ? base * ScoringConfig.easyWeight : base
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
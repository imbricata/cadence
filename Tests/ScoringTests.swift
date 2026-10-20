import XCTest
import Foundation
import CadenceCore

final class ScoringTests: XCTestCase {

    func testEasyWeightedMinutes() {
        XCTAssertEqual(easyWeightedMinutes(outcome: .full, minutes: 60), 60, accuracy: 0.001)
        XCTAssertEqual(easyWeightedMinutes(outcome: .easy, minutes: 60), 45, accuracy: 0.001)
        XCTAssertEqual(easyWeightedMinutes(outcome: .skipped, minutes: 60), 0, accuracy: 0.001)
        XCTAssertEqual(easyWeightedMinutes(outcome: .planned, minutes: 60), 0, accuracy: 0.001)
        XCTAssertEqual(easyWeightedMinutes(outcome: .easy, minutes: -5), 0, accuracy: 0.001)
    }

    func testExponentiallyWeightedAveragePrefersRecent() {
        // Half-life 7 days: today (age 0) should dominate an older sample (age 7).
        let avg = exponentiallyWeightedAverage(values: [100, 0], agesInDays: [0, 7], halfLife: 7)
        XCTAssertEqual(avg, 66.666, accuracy: 0.01)
    }

    func testExponentiallyWeightedAverageEmpty() {
        XCTAssertEqual(exponentiallyWeightedAverage(values: [], agesInDays: [], halfLife: 7), 0)
    }

    func testFormCalibratingWithoutTarget() {
        XCTAssertNil(formPercentage(recent: 50, reference: 50, daysObserved: 10, hasTarget: false))
    }

    func testFormPercentage() throws {
        let form = try XCTUnwrap(formPercentage(recent: 84, reference: 100, daysObserved: 20, hasTarget: false))
        XCTAssertEqual(form, 84, accuracy: 0.001)
    }

    func testFormCapAt200Percent() throws {
        let form = try XCTUnwrap(formPercentage(recent: 500, reference: 100, daysObserved: 30, hasTarget: false))
        XCTAssertEqual(form, 200, accuracy: 0.001)
    }

    func testFormWithTargetSkipsCalibration() throws {
        let form = try XCTUnwrap(formPercentage(recent: 60, reference: 80, daysObserved: 3, hasTarget: true))
        XCTAssertEqual(form, 75, accuracy: 0.001)
    }

    func testLevelThresholds() {
        XCTAssertEqual(level(forHours: 0), 0)
        XCTAssertEqual(level(forHours: 9), 0)
        XCTAssertEqual(level(forHours: 10), 1)
        XCTAssertEqual(level(forHours: 63), 3)
        XCTAssertEqual(level(forHours: 250), 5)
        XCTAssertEqual(level(forHours: 1000), 7)
    }

    func testFollowThroughPercent() {
        XCTAssertEqual(followThroughPercent(planned: 4, loggedWeight: 3)!, 75, accuracy: 0.001)
        XCTAssertEqual(followThroughPercent(planned: 0, loggedWeight: 0), nil)
        XCTAssertEqual(followThroughPercent(planned: 2, loggedWeight: 0)!, 0, accuracy: 0.001)
    }

    func testBlockLogWeight() {
        XCTAssertEqual(blockLogWeight(.full), 1.0)
        XCTAssertEqual(blockLogWeight(.easy), 0.75, accuracy: 0.001)
        XCTAssertEqual(blockLogWeight(.skipped), 0)
        XCTAssertEqual(blockLogWeight(.unlogged), 0)
    }

    func testTotalHours() {
        XCTAssertEqual(totalHours(minutes: 63), 1.05, accuracy: 0.001)
        XCTAssertEqual(totalHours(minutes: 0), 0)
    }

    func testProposeTargetMedian() {
        XCTAssertEqual(proposeTarget(weeklyMinutes: [100, 120, 90]), 100)
        XCTAssertEqual(proposeTarget(weeklyMinutes: [100, 120]), 110)
        XCTAssertNil(proposeTarget(weeklyMinutes: []))
    }

    func testDaysObserved() {
        let cal = Calendar.current
        let first = cal.date(byAdding: .day, value: -20, to: .now)!
        XCTAssertEqual(daysObserved(firstDate: first), 20)
    }

    func testFormReturnsNilWhenNoReference() {
        XCTAssertNil(formPercentage(recent: 50, reference: 0, daysObserved: 30, hasTarget: false))
    }

    func testDefaultMinutes() {
        XCTAssertEqual(defaultEntryMinutes(outcome: .full, blockMinutes: 60, itemCount: 2), 30)
        XCTAssertEqual(defaultEntryMinutes(outcome: .easy, blockMinutes: 60, itemCount: 2), 15)
        XCTAssertEqual(defaultEntryMinutes(outcome: .skipped, blockMinutes: 60, itemCount: 1), 0)
        XCTAssertEqual(defaultEntryMinutes(outcome: .planned, blockMinutes: 60, itemCount: 1), 0)
        XCTAssertEqual(defaultBlockMinutes(state: .full, plannedMinutes: 60), 60)
        XCTAssertEqual(defaultBlockMinutes(state: .easy, plannedMinutes: 60), 30)
        XCTAssertEqual(defaultBlockMinutes(state: .unlogged, plannedMinutes: 60), 0)
    }

    func testDenseAverageCountsZeroDays() {
        // One 70-minute day in a 7-day span: a plain average over days with data would say 70.
        let cal = Calendar.current
        let last = cal.startOfDay(for: .now)
        let first = cal.date(byAdding: .day, value: -6, to: last)!
        let avg = denseExponentialAverage(daily: [first: 70], firstDay: first, lastDay: last, halfLife: 1_000_000)
        XCTAssertEqual(avg, 10, accuracy: 0.01)
    }
}

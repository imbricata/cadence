import SwiftUI
import SwiftData
import Charts
import CadenceCore

/// One calm screen: follow-through, form per area, this week against targets, hours by activity.
struct InsightsView: View {
    @Environment(InsightsModel.self) private var insights
    @Query(sort: \Area.sortOrder) private var areas: [Area]
    @Query private var items: [Item]

    private var snapshot: InsightSnapshot { insights.snapshot }
    private var tracked: [Area] { areas.filter { !$0.isDeleted && !$0.isArchived && !$0.isClassesCalendar } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                followThrough
                form
                targets
                activities
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(Theme.Space.xl)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Insights")
    }

    // MARK: Follow-through

    private var followThrough: some View {
        section("Follow-through") {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                if let p = snapshot.followThrough.percent {
                    Text("\(Int(p.rounded()))%").font(.system(size: 44, weight: .semibold)).monospacedDigit()
                } else {
                    Text("—").font(.system(size: 44, weight: .semibold)).foregroundStyle(.secondary)
                }
                Text("of planned blocks, last 7 days").foregroundStyle(.secondary)
            }
            let weeks = snapshot.weeks.filter { $0.percent != nil }
            if weeks.count >= 2 {
                Chart(weeks, id: \.weekStart) { w in
                    LineMark(x: .value("Week", w.weekStart, unit: .weekOfYear), y: .value("Follow-through", w.percent ?? 0))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Color.accentColor)
                    PointMark(x: .value("Week", w.weekStart, unit: .weekOfYear), y: .value("Follow-through", w.percent ?? 0))
                        .foregroundStyle(Color.accentColor)
                }
                .chartYScale(domain: 0...100)
                .chartYAxis { AxisMarks(values: [0, 50, 100]) { AxisGridLine(); AxisValueLabel("\($0.as(Int.self) ?? 0)%") } }
                .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear)) { AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                .frame(height: 120)
            } else {
                Text("The weekly trend appears after a couple of weeks.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Form

    private var form: some View {
        section("Form") {
            if snapshot.areas.isEmpty {
                Text("Log some time to see form.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(snapshot.areas, id: \.areaId) { stat in
                if let area = areas.first(where: { $0.id == stat.areaId }) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            AreaDot(colorHex: area.colorHex)
                            Text(area.name)
                            Spacer()
                            PercentText(value: stat.formPercent).font(.callout)
                        }
                        FormBar(percent: stat.formPercent, colorHex: area.colorHex)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Text("The tick is 100%: your normal level, or your target once you set one.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Targets

    @ViewBuilder
    private var targets: some View {
        let withTarget = snapshot.areas.filter { $0.targetWeeklyMinutes != nil }
        if !withTarget.isEmpty {
            section("This week") {
                ForEach(withTarget, id: \.areaId) { stat in
                    if let area = areas.first(where: { $0.id == stat.areaId }), let target = stat.targetWeeklyMinutes {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                AreaDot(colorHex: area.colorHex)
                                Text(area.name)
                                Spacer()
                                Text("\(stat.weekMinutes) / \(target) min").font(.callout).monospacedDigit().foregroundStyle(.secondary)
                            }
                            ProgressView(value: min(1, Double(stat.weekMinutes) / Double(max(1, target))))
                                .tint(area.color.base)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    // MARK: Hours

    private var activities: some View {
        section("Hours") {
            let stats = snapshot.activities.filter { $0.rawMinutes > 0 }
            if stats.isEmpty {
                Text("No logged hours yet.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(tracked) { area in
                let rows = stats
                    .compactMap { s in items.first(where: { $0.id == s.itemId && $0.areaId == area.id }).map { ($0, s) } }
                    .sorted { $0.1.rawMinutes > $1.1.rawMinutes }
                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        HStack(spacing: 6) { AreaDot(colorHex: area.colorHex, size: 8); Text(area.name).font(.subheadline.weight(.semibold)) }
                        ForEach(rows, id: \.0.id) { item, s in
                            HStack {
                                Text(item.title)
                                Spacer()
                                Text(s.level > 0 ? "\(Format.hours(minutes: s.rawMinutes)) · Level \(s.level)" : Format.hours(minutes: s.rawMinutes))
                                    .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                            }
                            .padding(.leading, 14)
                        }
                    }
                    .padding(.bottom, Theme.Space.xs)
                }
            }
        }
    }

    // MARK: Layout

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(title).font(.headline)
            content()
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(.quaternary.opacity(0.5)))
    }
}

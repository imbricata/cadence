import SwiftUI
import SwiftData
import CadenceCore

struct InsightsView: View {
    @Environment(AppStore.self) private var store
    @Environment(GoogleService.self) private var google
    @Query(sort: \Area.sortOrder) private var areas: [Area]
    @Query private var items: [Item]
    @Query private var blockLogs: [BlockLog]
    @Query private var entries: [BlockEntry]
    @Query private var unplanned: [UnplannedLog]
    @Query private var targets: [Target]

    private var snapshot: InsightSnapshot {
        _ = (areas, items, blockLogs, entries, unplanned, targets)
        return computeInsights(context: store.context, events: google.cachedEvents)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                followThroughCard
                formCard
                activitiesCard
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .navigationTitle("Insights")
    }

    private var followThroughCard: some View {
        let ft = snapshot.followThrough
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Follow-through").font(.headline)
                Spacer()
                if let p = ft.percent {
                    Text("\(Int(p.rounded()))%")
                        .font(.headline).monospacedDigit()
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            Text("Last 7 days")
                .font(.caption)
                .foregroundStyle(.secondary)
            FollowThroughChart(days: ft.days)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
    }

    private var formCard: some View {
        let stats = snapshot.areas
        return VStack(alignment: .leading, spacing: 12) {
            Text("Form").font(.headline)
            if stats.isEmpty {
                Text("Log some time to see form.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(stats, id: \.areaId) { stat in
                let name = areas.first { $0.id == stat.areaId }?.name ?? ""
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(name)
                        Spacer()
                        FormLabel(percent: stat.formPercent)
                    }
                    FormBar(percent: stat.formPercent)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
    }

    private var activitiesCard: some View {
        let stats = snapshot.activities.filter { $0.rawMinutes > 0 }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Hours by activity").font(.headline)
            if stats.isEmpty {
                Text("No logged hours yet.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(stats.sorted { $0.rawMinutes > $1.rawMinutes }, id: \.itemId) { stat in
                let title = items.first { $0.id == stat.itemId }?.title ?? ""
                let areaId = items.first { $0.id == stat.itemId }?.areaId
                HStack {
                    if let area = areas.first(where: { $0.id == areaId }) {
                        AreaColorDot(colorHex: area.colorHex)
                    }
                    VStack(alignment: .leading) {
                        Text(title)
                        Text(levelLabel(hours: totalHours(minutes: stat.rawMinutes), levelIndex: stat.level))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(format: "%.1f h", totalHours(minutes: stat.rawMinutes)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
    }
}
import SwiftUI
import SwiftData
import CadenceCore

struct BacklogView: View {
    @Query(sort: \Area.sortOrder) private var areas: [Area]
    @Query private var items: [Item]

    private var visibleAreas: [Area] {
        areas.filter { !$0.isDeleted && !$0.isArchived && !$0.isClassesCalendar }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(visibleAreas) { area in
                    AreaBacklogSection(area: area, items: items.filter { $0.areaId == area.id && !$0.isDeleted })
                }
                if openTasks(in: items).isEmpty && activities(in: items).isEmpty {
                    Text("Your backlog is empty.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .padding(12)
        }
        .background(.background)
    }

    private func openTasks(in items: [Item]) -> [Item] {
        items.filter { $0.kind == .task && $0.status == .open }
    }
    private func activities(in items: [Item]) -> [Item] {
        items.filter { $0.kind == .activity }
    }
}

struct AreaBacklogSection: View {
    let area: Area
    let items: [Item]

    private var tasks: [Item] {
        items.filter { $0.kind == .task && $0.status == .open }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }
    private var activities: [Item] {
        items.filter { $0.kind == .activity }.sorted { $0.title < $1.title }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                AreaColorDot(colorHex: area.colorHex)
                Text(area.name).font(.headline)
                Spacer()
            }
            ForEach(tasks) { item in
                HStack(spacing: 6) {
                    Image(systemName: "circle").font(.caption).foregroundStyle(.secondary)
                    Text(item.title).font(.callout)
                    Spacer()
                    if let due = item.dueDate {
                        Text(due, format: .dateTime.month(.abbreviated).day())
                            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .contentShape(Rectangle())
                .draggable(item.id.uuidString)
            }
            ForEach(activities) { item in
                HStack(spacing: 6) {
                    Image(systemName: "arrow.2.circlepath").font(.caption).foregroundStyle(.tertiary)
                    Text(item.title).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
                .draggable(item.id.uuidString)
            }
        }
    }
}
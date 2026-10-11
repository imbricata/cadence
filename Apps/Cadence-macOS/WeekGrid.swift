import SwiftUI
import CadenceCore

struct WeekGrid: View {
    let week: Date
    let events: [CalendarEvent]
    let areaFor: (String) -> Area?

    var onOpenEvent: (CalendarEvent) -> Void = { _ in }
    var onCreateAt: (Date) -> Void = { _ in }
    var onMoveEvent: (CalendarEvent, Date) -> Void = { _, _ in }
    var onResizeEvent: (CalendarEvent, Date) -> Void = { _, _ in }
    var onDropItem: (String, CalendarEvent) -> Void = { _, _ in }

    private let hourHeight: CGFloat = 48
    private let gutterWidth: CGFloat = 44

    private var days: [Date] {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: week))!
        return (0..<7).map { cal.date(byAdding: .day, value: $0, to: start)! }
    }

    private var totalHeight: CGFloat { CGFloat(24) * hourHeight }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: gutterWidth)
                ForEach(days, id: \.self) { day in
                    VStack(spacing: 2) {
                        Text(day, format: .dateTime.weekday(.abbreviated))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(day, format: .dateTime.day())
                            .font(.headline)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(Calendar.current.isDateInToday(day) ? Color.accentColor.opacity(0.12) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal, 4)

            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    Gutter(height: totalHeight, hourHeight: hourHeight)
                    GeometryReader { geo in
                        let colWidth = geo.size.width / 7
                        HStack(spacing: 0) {
                            ForEach(days, id: \.self) { day in
                                DayColumn(
                                    day: day,
                                    events: eventsInDay(day),
                                    width: colWidth,
                                    hourHeight: hourHeight,
                                    totalHeight: totalHeight,
                                    areaFor: areaFor,
                                    onOpenEvent: onOpenEvent,
                                    onCreateAt: onCreateAt,
                                    onMoveEvent: onMoveEvent,
                                    onResizeEvent: onResizeEvent,
                                    onDropItem: onDropItem
                                )
                            }
                        }
                    }
                    .frame(height: totalHeight)
                }
            }
        }
    }

    private func eventsInDay(_ day: Date) -> [CalendarEvent] {
        let interval = Calendar.current.dateInterval(of: .day, for: day)!
        return events.filter { $0.start < interval.end && $0.end > interval.start }
    }
}

struct Gutter: View {
    let height: CGFloat
    let hourHeight: CGFloat
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Text(hourLabel(hour))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .frame(height: hourHeight, alignment: .top)
                    .frame(width: 40)
                    .offset(y: -5)
            }
        }
        .frame(height: height)
    }

    private func hourLabel(_ h: Int) -> String {
        if h == 0 { return "" }
        let d = DateFormatter()
        d.dateFormat = "ha"
        let date = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: .now)!
        return d.string(from: date).lowercased()
    }
}

struct DayColumn: View {
    let day: Date
    let events: [CalendarEvent]
    let width: CGFloat
    let hourHeight: CGFloat
    let totalHeight: CGFloat
    let areaFor: (String) -> Area?

    var onOpenEvent: (CalendarEvent) -> Void
    var onCreateAt: (Date) -> Void
    var onMoveEvent: (CalendarEvent, Date) -> Void
    var onResizeEvent: (CalendarEvent, Date) -> Void
    var onDropItem: (String, CalendarEvent) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.primary.opacity(0.05))
                        .frame(height: hourHeight)
                        .overlay(alignment: .top) { Divider().opacity(0.5) }
                }
            }
            ForEach(layout(), id: \.event.id) { item in
                EventBlock(
                    event: item.event,
                    area: areaFor(item.event.calendarId),
                    width: itemWidth(item),
                    hourHeight: hourHeight,
                    exceedable: areaFor(item.event.calendarId)?.isClassesCalendar == false,
                    onOpen: { onOpenEvent(item.event) },
                    onMove: { newStart in onMoveEvent(item.event, newStart) },
                    onResize: { newEnd in onResizeEvent(item.event, newEnd) },
                    onDropItem: { id in onDropItem(id, item.event) }
                )
                .offset(x: itemX(item), y: yOffset(item.event))
                .frame(height: eventHeight(item.event))
            }
        }
        .frame(width: width, height: totalHeight)
        .overlay(alignment: .leading) { Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 0.5) }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onEnded { value in
                    onCreateAt(startTime(forY: value.location.y))
                }
        )
    }

    private func startTime(forY y: CGFloat) -> Date {
        let minutes = max(0, min(24 * 60, y / hourHeight * 60))
        let rounded = (minutes / 15).rounded() * 15
        return Calendar.current.date(bySettingHour: Int(rounded) / 60, minute: Int(rounded) % 60, second: 0, of: day) ?? day
    }

    private struct LaidOut {
        let event: CalendarEvent
        let lane: Int
        let laneCount: Int
    }

    private func itemWidth(_ item: LaidOut) -> CGFloat { width / CGFloat(item.laneCount) }
    private func itemX(_ item: LaidOut) -> CGFloat { CGFloat(item.lane) * itemWidth(item) }

    private func layout() -> [LaidOut] {
        let sorted = events.sorted { $0.start < $1.start }
        var laneEnds: [Date] = []
        var result: [(CalendarEvent, Int)] = []
        for e in sorted {
            if let l = laneEnds.firstIndex(where: { $0 <= e.start }) {
                laneEnds[l] = e.end
                result.append((e, l))
            } else {
                laneEnds.append(e.end)
                result.append((e, laneEnds.count - 1))
            }
        }
        let count = max(laneEnds.count, 1)
        return result.map { LaidOut(event: $0.0, lane: $0.1, laneCount: count) }
    }

    private func yOffset(_ event: CalendarEvent) -> CGFloat {
        let dayStart = Calendar.current.startOfDay(for: day)
        let minutes = max(0, event.start.timeIntervalSince(dayStart) / 60)
        return CGFloat(minutes) / 60 * hourHeight
    }

    private func eventHeight(_ event: CalendarEvent) -> CGFloat {
        let mins = max(15, event.end.timeIntervalSince(event.start) / 60)
        return max(CGFloat(mins) / 60 * hourHeight, 22)
    }
}

struct EventBlock: View {
    let event: CalendarEvent
    let area: Area?
    let width: CGFloat
    let hourHeight: CGFloat
    let exceedable: Bool
    var onOpen: () -> Void
    var onMove: (Date) -> Void
    var onResize: (Date) -> Void
    var onDropItem: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(event.summary)
                .font(.caption2)
                .lineLimit(2)
            Text(event.start, format: .dateTime.hour().minute())
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .padding(3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 5).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(stroke, lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .dropDestination(for: String.self) { ids, _ in
            guard exceedable else { return false }
            for id in ids { onDropItem(id) }
            return true
        }
        .overlay(alignment: .bottom) {
            if exceedable {
                Rectangle()
                    .fill(Color.primary.opacity(0.3))
                    .frame(height: 3)
                    .gesture(
                        DragGesture()
                            .onEnded { value in
                                let delta = value.translation.height / hourHeight * 3600
                                onResize(event.end.addingTimeInterval(delta))
                            }
                    )
            }
        }
        .gesture(DragGesture().onEnded { value in
            guard exceedable else { return }
            let delta = value.translation.height / hourHeight * 3600
            onMove(event.start.addingTimeInterval(delta))
        })
    }

    private var fill: Color {
        if area?.isClassesCalendar == true { return Color.secondary.opacity(0.16) }
        return Color(hex: area?.colorHex ?? "#888C96").opacity(0.22)
    }
    private var stroke: Color {
        if area?.isClassesCalendar == true { return Color.secondary.opacity(0.4) }
        return Color(hex: area?.colorHex ?? "#888C96").opacity(0.7)
    }
}
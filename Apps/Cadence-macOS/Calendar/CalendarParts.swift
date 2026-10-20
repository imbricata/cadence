import SwiftUI
import CadenceCore

/// Hour labels down the left edge.
struct TimeGutter: View {
    let hourHeight: CGFloat
    let width: CGFloat

    private static let hours: [Date] = {
        let start = Calendar.current.startOfDay(for: .now)
        return (0..<24).map { Calendar.current.date(byAdding: .hour, value: $0, to: start)! }
    }()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(1..<24, id: \.self) { h in
                Text(Self.hours[h], format: .dateTime.hour())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .offset(y: CGFloat(h) * hourHeight - 6)
                    .padding(.trailing, Theme.Space.s)
            }
        }
        .frame(width: width, height: hourHeight * 24, alignment: .topTrailing)
        .accessibilityHidden(true)
    }
}

/// Grid lines, weekend tint, off-hours shading and the today column tint.
struct GridBackground: View {
    let days: [Date]
    let colWidth: CGFloat
    let hourHeight: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let cal = Calendar.current
            let hour = hourHeight
            for (i, day) in days.enumerated() {
                let x = CGFloat(i) * colWidth
                let col = CGRect(x: x, y: 0, width: colWidth, height: size.height)
                if cal.isDateInToday(day) {
                    ctx.fill(Path(col), with: .color(Color.accentColor.opacity(0.05)))
                } else if cal.isDateInWeekend(day), days.count > 1 {
                    ctx.fill(Path(col), with: .color(Color.primary.opacity(0.025)))
                }
            }
            // Off-hours (before 07:00, after 23:00) are barely shaded.
            let shade = Color.primary.opacity(0.03)
            ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: hour * 7)), with: .color(shade))
            ctx.fill(Path(CGRect(x: 0, y: hour * 23, width: size.width, height: hour)), with: .color(shade))

            for h in 0...48 {
                let y = CGFloat(h) * hour / 2
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(line, with: .color(Color.primary.opacity(h % 2 == 0 ? 0.08 : 0.035)), lineWidth: 0.5)
            }
            for i in 0...days.count {
                let x = CGFloat(i) * colWidth
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(line, with: .color(Color.primary.opacity(0.08)), lineWidth: 0.5)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Day headers plus the all-day / deadline strip.
struct CalendarHeader: View {
    let days: [Date]
    let events: [CalendarEvent]
    let areaFor: (String) -> Area?
    let gutter: CGFloat
    let colWidth: CGFloat
    var onSelectDay: (Date) -> Void

    private var maxChips: Int { 2 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: gutter, height: 1)
                ForEach(days, id: \.self) { day in
                    dayHeader(day).frame(width: colWidth)
                }
            }
            .padding(.vertical, Theme.Space.s)

            let perDay = days.map { EventLayout.allDayItems(events, on: $0) }
            if perDay.contains(where: { !$0.isEmpty }) {
                HStack(alignment: .top, spacing: 0) {
                    Text("all-day")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: gutter, alignment: .trailing)
                        .padding(.trailing, Theme.Space.s)
                    ForEach(Array(days.enumerated()), id: \.offset) { i, _ in
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(perDay[i].prefix(maxChips)) { chip($0) }
                            if perDay[i].count > maxChips {
                                Text("+\(perDay[i].count - maxChips) more")
                                    .font(.caption2).foregroundStyle(.secondary)
                                    .help(perDay[i].dropFirst(maxChips).map(\.summary).joined(separator: "\n"))
                            }
                        }
                        .frame(width: colWidth, alignment: .leading)
                        .padding(.horizontal, 2)
                    }
                }
                .padding(.bottom, Theme.Space.s)
            }
        }
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func dayHeader(_ day: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(day)
        return Button { onSelectDay(day) } label: {
            VStack(spacing: 2) {
                Text(day, format: days.count == 1 ? .dateTime.weekday(.wide) : .dateTime.weekday(.abbreviated))
                    .font(.caption)
                    .foregroundStyle(isToday ? Color.accentColor : .secondary)
                Text(day, format: .dateTime.day())
                    .font(.title3.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Color.white : .primary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(isToday ? Color.accentColor : .clear))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
    }

    private func chip(_ e: CalendarEvent) -> some View {
        let area = areaFor(e.calendarId)
        let color = area?.color ?? .classes
        return HStack(spacing: 3) {
            if e.isDeadline { Image(systemName: "flag.fill").font(.system(size: 8)).foregroundStyle(color.base) }
            Text(e.summary).lineLimit(1)
            if e.isDeadline, colWidth > 120 {
                Text(e.start, format: .dateTime.hour().minute()).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .font(.caption)
        .padding(.horizontal, 6)
        .frame(height: 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 4).fill(e.isDeadline ? Color.secondary.opacity(0.10) : color.fill))
        .help(e.summary)
    }
}

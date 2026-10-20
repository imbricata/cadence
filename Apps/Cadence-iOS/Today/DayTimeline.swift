import SwiftUI
import CadenceCore

struct TimelineActions {
    var open: (CalendarEvent, Area) -> Void
    var openReadOnly: (CalendarEvent) -> Void
    var create: (Double) -> Void
    var log: (CalendarEvent, Area, BlockLogState) -> Void
    var changeArea: (CalendarEvent, Area, Area) -> Void
    var delete: (CalendarEvent) -> Void
}

/// One day as a vertical timeline: hour gutter, Classes in grey, Area blocks in their colours, now line.
struct DayTimeline: View {
    let day: Date
    let events: [CalendarEvent]
    let areas: [Area]
    let info: BlockInfoIndex
    let actions: TimelineActions

    // The timeline grows with Dynamic Type so labels and blocks stay readable.
    @ScaledMetric(relativeTo: .body) private var hourHeight: CGFloat = 56
    @ScaledMetric(relativeTo: .caption) private var scaledGutter: CGFloat = 52
    private var gutter: CGFloat { min(scaledGutter, 76) }

    @State private var scroll = ScrollPosition(y: 0)

    private var areaByCalendar: [String: Area] {
        Dictionary(areas.filter { !$0.isDeleted && !$0.googleCalendarId.isEmpty }.map { ($0.googleCalendarId, $0) }, uniquingKeysWith: { a, _ in a })
    }
    private var selectableAreas: [Area] { areas.filter { !$0.isDeleted && !$0.isArchived && !$0.isClassesCalendar } }
    private var allDay: [CalendarEvent] { EventLayout.allDayItems(events, on: day) }
    private var laidOut: [PositionedEvent] { EventLayout.layout(events, on: day) }

    var body: some View {
        VStack(spacing: 0) {
            if !allDay.isEmpty { allDayStrip.padding(.top, Theme.Space.s) }
            GeometryReader { geo in
                let width = geo.size.width - gutter - Theme.Space.s
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        hourLines
                        Color.clear
                            .frame(width: width, height: hourHeight * 24)
                            .contentShape(Rectangle())
                            .offset(x: gutter)
                            .onTapGesture(coordinateSpace: .local) { p in
                                let m = min(1380, max(0, EventLayout.snapDown(Double(p.y / hourHeight) * 60)))
                                actions.create(m)
                            }
                        ForEach(laidOut) { p in block(p, width: width) }
                        nowLine(width: width)
                    }
                    .frame(width: geo.size.width, height: hourHeight * 24, alignment: .topLeading)
                }
                .scrollPosition($scroll)
                .overlay(alignment: .top) {
                    if laidOut.isEmpty && allDay.isEmpty {
                        EmptyLine(text: "Nothing planned. Tap the timeline to add a block.")
                            .padding(.top, hourHeight * 1.5)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .onAppear { scrollToDefault() }
    }

    // MARK: Pieces

    private var hourLines: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<24, id: \.self) { h in
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 0.5)
                    .padding(.leading, gutter)
                    .offset(y: CGFloat(h) * hourHeight)
                if h > 0 {
                    Text(Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: day) ?? day, format: .dateTime.hour())
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: gutter - 8, alignment: .trailing)
                        .offset(y: CGFloat(h) * hourHeight - 7)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var allDayStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(allDay.prefix(3)) { e in
                let area = areaByCalendar[e.calendarId]
                HStack(spacing: 6) {
                    if e.isDeadline { Image(systemName: "flag.fill").font(.caption2).foregroundStyle((area?.color ?? .classes).base) }
                    Text(e.summary).lineLimit(1)
                    if e.isDeadline {
                        Text(e.start, format: .dateTime.hour().minute()).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Spacer(minLength: 0)
                }
                .font(.footnote)
                .padding(.horizontal, 8)
                .frame(minHeight: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(e.isDeadline ? Color.secondary.opacity(0.10) : (area?.color ?? .classes).fill))
                .onTapGesture { actions.openReadOnly(e) }
            }
            if allDay.count > 3 {
                Text("+\(allDay.count - 3) more").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.bottom, Theme.Space.s)
    }

    @ViewBuilder
    private func block(_ p: PositionedEvent, width: CGFloat) -> some View {
        let area = areaByCalendar[p.event.calendarId]
        let editable = area != nil && area?.isClassesCalendar == false
        let laneW = p.laneCount == 1 ? width : width * max(0.5, 1 - 0.3 * CGFloat(p.laneCount - 1))
        let step = p.laneCount == 1 ? 0 : (width - laneW) / CGFloat(p.laneCount - 1)
        let h = max(CGFloat(p.endMinute - p.startMinute) / 60 * hourHeight - 2, 22)
        let rect = CGRect(x: gutter + CGFloat(p.lane) * step, y: CGFloat(p.startMinute) / 60 * hourHeight + 1, width: laneW, height: h)

        TimelineBlock(positioned: p, area: area, info: info.info(for: p.event), size: rect.size)
            .contentShape(Rectangle())
            .onTapGesture {
                if let area, editable { actions.open(p.event, area) } else { actions.openReadOnly(p.event) }
            }
            .contextMenu {
                if let area, editable {
                    Menu("Log") {
                        ForEach([BlockLogState.full, .easy, .skipped], id: \.self) { s in
                            Button { actions.log(p.event, area, s) } label: { Label(OutcomeStyle.title(s), systemImage: OutcomeStyle.symbol(s)) }
                        }
                        Button("Clear Log") { actions.log(p.event, area, .unlogged) }
                    }
                    Menu("Change Area") {
                        ForEach(selectableAreas.filter { $0.id != area.id }) { a in
                            Button(a.name) { actions.changeArea(p.event, area, a) }
                        }
                    }
                    Button("Delete", role: .destructive) { actions.delete(p.event) }
                }
            }
            .position(x: rect.midX, y: rect.midY)
            .zIndex(1 + Double(p.lane) * 0.1)
    }

    @ViewBuilder
    private func nowLine(width: CGFloat) -> some View {
        if Calendar.current.isDateInToday(day) {
            TimelineView(.everyMinute) { ctx in
                let y = CGFloat(EventLayout.minuteOfDay(ctx.date, on: day)) / 60 * hourHeight
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Color.accentColor).frame(width: width, height: 1.5).offset(x: gutter, y: y)
                    Circle().fill(Color.accentColor).frame(width: 8, height: 8).offset(x: gutter - 4, y: y - 3.5)
                }
                .frame(width: gutter + width, height: hourHeight * 24, alignment: .topLeading)
            }
            .allowsHitTesting(false)
            .zIndex(20)
        }
    }

    private func scrollToDefault() {
        var hour = 7.0
        if Calendar.current.isDateInToday(day) {
            let now = EventLayout.minuteOfDay(.now, on: day) / 60
            hour = (7..<23).contains(Int(now)) ? max(0, now - 1.5) : 7   // late night / early morning: start at 07:00
        } else if let first = laidOut.first {
            hour = max(0, first.startMinute / 60 - 1)
        }
        Task { @MainActor in scroll.scrollTo(y: CGFloat(hour) * hourHeight) }
    }
}

/// Appearance of one block on the iPhone timeline.
struct TimelineBlock: View {
    let positioned: PositionedEvent
    let area: Area?
    let info: BlockInfo?
    let size: CGSize

    private var event: CalendarEvent { positioned.event }
    private var isClasses: Bool { area?.isClassesCalendar ?? true }
    private var color: AreaColor { area?.color ?? .classes }
    private var state: BlockLogState { info?.state ?? .unlogged }
    private var covered: Bool { positioned.laneCount > 1 && positioned.lane < positioned.laneCount - 1 }
    private var isPastUnlogged: Bool { !isClasses && event.end < .now && state == .unlogged }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Theme.Radius.block, style: .continuous)
                .fill(isClasses ? Color.secondary.opacity(0.13) : color.fill)
            if !isClasses {
                RoundedRectangle(cornerRadius: 1.5).fill(color.base).frame(width: 3).padding(.vertical, 3).padding(.leading, 3)
            }
            content.padding(.leading, isClasses ? 8 : 11).padding(.trailing, 8).padding(.vertical, size.height < 40 ? 1 : 5)
            if !isClasses, state != .unlogged {
                Image(systemName: OutcomeStyle.symbol(state))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color.base)
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.block, style: .continuous)
                .strokeBorder(isPastUnlogged ? color.stroke : .clear, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var content: some View {
        let title = event.summary.isEmpty ? (area?.name ?? "") : event.summary
        if covered {
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
        } else if size.height < 40 {
            HStack(spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(event.start, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(Format.timeRange(event.start, event.end)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                let lines = max(0, Int((size.height - 10 - 36) / 15))
                if lines > 0, let titles = info?.itemTitles {
                    ForEach(titles.prefix(min(2, lines)), id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
            }
        }
    }

    private var accessibilityText: String {
        let title = event.summary.isEmpty ? (area?.name ?? "") : event.summary
        var text = "\(title), \(Format.timeRange(event.start, event.end))"
        if !isClasses, state != .unlogged { text += ", logged \(OutcomeStyle.title(state))" }
        return text
    }
}

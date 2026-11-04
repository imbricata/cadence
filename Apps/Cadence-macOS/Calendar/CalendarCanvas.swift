import SwiftUI
import CadenceCore

struct CreateRequest: Equatable {
    var day: Date
    var startMinute: Double
}

/// The day / week calendar. Owns every interaction: create by dragging, move, resize, select, open, delete, drop.
struct CalendarCanvas: View {
    let days: [Date]
    let events: [CalendarEvent]
    let areas: [Area]
    let info: BlockInfoIndex
    @Binding var selectedId: String?
    @Binding var createRequest: CreateRequest?
    var scrollToken: Int
    var onSelectDay: (Date) -> Void

    @Environment(GoogleService.self) private var google
    @Environment(AppStore.self) private var store

    private let gutter: CGFloat = 54
    private var hourHeight: CGFloat { Theme.hourHeight }

    enum Interaction: Equatable {
        case creating(dayIndex: Int, start: Double, end: Double)
        case moving(id: String, dayIndex: Int, start: Double)
        case resizing(id: String, dayIndex: Int, start: Double, end: Double)
    }

    @State private var interaction: Interaction?
    @State private var dragActive = false
    @State private var cancelled = false
    @State private var showCreatePopover = false
    @State private var openId: String?
    @State private var scroll = ScrollPosition(y: 0)
    @State private var deleteCandidate: CalendarEvent?
    @FocusState private var focused: Bool
    #if DEBUG
    @State private var didDebugOpen = false
    #endif

    // MARK: Derived

    private var areaByCalendar: [String: Area] {
        Dictionary(areas.filter { !$0.isDeleted && !$0.googleCalendarId.isEmpty }.map { ($0.googleCalendarId, $0) }, uniquingKeysWith: { a, _ in a })
    }
    private var selectableAreas: [Area] {
        areas.filter { !$0.isDeleted && !$0.isArchived && !$0.isClassesCalendar }
    }

    private func isEditable(_ p: PositionedEvent) -> Bool {
        guard let area = areaByCalendar[p.event.calendarId], !area.isClassesCalendar else { return false }
        return !p.clippedStart && !p.clippedEnd && !p.event.isAllDayLike && !p.event.id.hasPrefix("local-")
    }

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            let colW = max(48, (geo.size.width - gutter) / CGFloat(max(1, days.count)))
            VStack(spacing: 0) {
                CalendarHeader(days: days, events: events, areaFor: { areaByCalendar[$0] }, gutter: gutter, colWidth: colW, onSelectDay: onSelectDay)
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        TimeGutter(hourHeight: hourHeight, width: gutter)
                        grid(colW: colW)
                    }
                    .frame(height: hourHeight * 24)
                }
                .scrollPosition($scroll)
            }
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.return) {
            guard let id = selectedId else { return .ignored }
            openId = id
            return .handled
        }
        .onKeyPress(.delete) { deleteSelected() }
        .onKeyPress(.deleteForward) { deleteSelected() }
        .onKeyPress(.escape) {
            if interaction != nil { cancelInteraction(); return .handled }
            if selectedId != nil { selectedId = nil; return .handled }
            return .ignored
        }
        .onAppear { scrollToDefault() }
        #if DEBUG
        .task(id: events.count) { await debugOpen() }
        #endif
        .onChange(of: scrollToken) { scrollToDefault() }
        .onChange(of: createRequest) { _, req in
            guard let req else { return }
            createRequest = nil
            let i = days.firstIndex { Calendar.current.isDate($0, inSameDayAs: req.day) } ?? 0
            interaction = .creating(dayIndex: i, start: req.startMinute, end: min(1440, req.startMinute + 60))
            scroll.scrollTo(y: max(0, CGFloat(req.startMinute) / 60 * hourHeight - 2 * hourHeight))
            Task { @MainActor in showCreatePopover = true }
        }
        .onChange(of: showCreatePopover) { _, shown in
            if !shown, case .creating = interaction { interaction = nil }
        }
        .confirmationDialog(
            "Delete this block?",
            isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Block", role: .destructive) {
                if let e = deleteCandidate { Task { await google.deleteBlock(event: e) } }
                deleteCandidate = nil
            }
        } message: {
            Text("It has been logged. The log stays in your history.")
        }
    }

    // MARK: Grid

    private func grid(colW: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            GridBackground(days: days, colWidth: colW, hourHeight: hourHeight)

            // Empty-space surface: drag to create, double-click for a 1 h block, click to deselect, drop items.
            Color.clear
                .contentShape(Rectangle())
                .gesture(createGesture(colW: colW))
                .onTapGesture(count: 2, coordinateSpace: .local) { doubleClickCreate($0, colW: colW) }
                .onTapGesture { selectedId = nil; openId = nil; focused = true }
                .dropDestination(for: String.self) { ids, location in
                    dropOnEmpty(ids, at: location, colW: colW)
                }

            ForEach(days.indices, id: \.self) { i in
                ForEach(EventLayout.layout(events, on: days[i])) { p in
                    block(p, dayIndex: i, colW: colW)
                }
            }

            ghost(colW: colW)
            nowLine(colW: colW)
        }
        .frame(width: colW * CGFloat(days.count), height: hourHeight * 24, alignment: .topLeading)
    }

    // MARK: Blocks

    private func frame(for p: PositionedEvent, dayIndex: Int, colW: CGFloat) -> (rect: CGRect, range: (Date, Date)?) {
        var di = dayIndex
        var s = p.startMinute, e = p.endMinute
        var lane = p.lane, laneCount = p.laneCount
        var range: (Date, Date)?
        switch interaction {
        case .moving(let id, let nd, let ns) where id == p.id:
            let dur = p.event.end.timeIntervalSince(p.event.start) / 60
            di = nd; s = ns; e = min(1440, ns + dur); lane = 0; laneCount = 1
            let start = EventLayout.date(on: days[nd], minute: ns)
            range = (start, start.addingTimeInterval(dur * 60))
        case .resizing(let id, let nd, let ns, let ne) where id == p.id:
            di = nd; s = ns; e = ne; lane = 0; laneCount = 1
            range = (EventLayout.date(on: days[nd], minute: ns), EventLayout.date(on: days[nd], minute: ne))
        default: break
        }
        // Overlapping blocks share the column width side by side, so none of them covers another.
        let laneW = colW / CGFloat(max(1, laneCount))
        let rect = CGRect(
            x: CGFloat(di) * colW + CGFloat(lane) * laneW + 1.5,
            y: CGFloat(s) / 60 * hourHeight + 1,
            width: laneW - 3,
            height: max(CGFloat(e - s) / 60 * hourHeight - 2, 18)
        )
        return (rect, range)
    }

    @ViewBuilder
    private func block(_ p: PositionedEvent, dayIndex: Int, colW: CGFloat) -> some View {
        let area = areaByCalendar[p.event.calendarId]
        let editable = isEditable(p)
        let layout = frame(for: p, dayIndex: dayIndex, colW: colW)
        let active: Bool = {
            switch interaction {
            case .moving(let id, _, _), .resizing(let id, _, _, _): return id == p.id
            default: return false
            }
        }()

        EventBlockView(
            positioned: p, area: area, info: info.info(for: p.event), size: layout.rect.size,
            isSelected: selectedId == p.id, isEditable: editable, isDragging: active, previewRange: layout.range,
            onTap: {
                selectedId = p.id
                focused = true
                if area == nil || area?.isClassesCalendar == true { openId = p.id }
            },
            onDoubleTap: { selectedId = p.id; openId = p.id },
            onMove: { t, ended in handleMove(p, dayIndex: dayIndex, translation: t, ended: ended, colW: colW) },
            onResize: { edge, dy, ended in handleResize(p, dayIndex: dayIndex, edge: edge, dy: dy, ended: ended) },
            onDrop: { ids in dropOnBlock(ids, p, area: area) }
        )
        .popover(
            isPresented: Binding(get: { openId == p.id }, set: { if !$0, openId == p.id { openId = nil } }),
            arrowEdge: .trailing
        ) {
            if let area, !area.isClassesCalendar {
                BlockDetailView(event: p.event, area: area, presentation: .popover)
            } else {
                ReadOnlyEventView(event: p.event)
            }
        }
        .contextMenu { if let area, editable { blockMenu(p.event, area) } }
        .position(x: layout.rect.midX, y: layout.rect.midY)
        .zIndex(active ? 10 : (selectedId == p.id ? 5 : 1 + Double(p.lane) * 0.1))
    }

    @ViewBuilder
    private func blockMenu(_ event: CalendarEvent, _ area: Area) -> some View {
        Button("Open") { openId = event.id }
        Menu("Log") {
            ForEach([BlockLogState.full, .easy, .skipped], id: \.self) { s in
                Button { logBlock(store, BlockRef(event: event, areaId: area.id), state: s) } label: {
                    Label(OutcomeStyle.title(s), systemImage: OutcomeStyle.symbol(s))
                }
            }
            Divider()
            Button("Clear Log") { logBlock(store, BlockRef(event: event, areaId: area.id), state: .unlogged) }
        }
        Menu("Change Area") {
            ForEach(selectableAreas.filter { $0.id != area.id }) { a in
                Button(a.name) { Task { await google.changeBlockArea(event: event, from: area, to: a) } }
            }
        }
        Divider()
        Button("Delete", role: .destructive) { requestDelete(event) }
    }

    // MARK: Create

    private func createGesture(colW: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .local)
            .onChanged { v in
                if !dragActive { dragActive = true; cancelled = false; selectedId = nil; openId = nil; focused = true }
                guard !cancelled else { return }
                let i = dayIndex(forX: v.startLocation.x, colW: colW)
                let a = EventLayout.snap(minutes(forY: v.startLocation.y))
                let b = EventLayout.snap(minutes(forY: v.location.y))
                let lo = max(0, min(a, b)), hi = min(1440, max(a, b))
                interaction = .creating(dayIndex: i, start: lo, end: max(hi, min(1440, lo + 15)))
            }
            .onEnded { _ in
                defer { dragActive = false; cancelled = false }
                guard !cancelled, case .creating = interaction else { return }
                showCreatePopover = true
            }
    }

    private func doubleClickCreate(_ point: CGPoint, colW: CGFloat) {
        let i = dayIndex(forX: point.x, colW: colW)
        let start = min(1380, max(0, EventLayout.snapDown(minutes(forY: point.y))))
        interaction = .creating(dayIndex: i, start: start, end: start + 60)
        Task { @MainActor in showCreatePopover = true }
    }

    @ViewBuilder
    private func ghost(colW: CGFloat) -> some View {
        if case .creating(let di, let s, let e) = interaction, days.indices.contains(di) {
            let rect = CGRect(
                x: CGFloat(di) * colW + 1.5, y: CGFloat(s) / 60 * hourHeight + 1,
                width: colW - 3, height: max(CGFloat(e - s) / 60 * hourHeight - 2, 18)
            )
            RoundedRectangle(cornerRadius: Theme.Radius.block, style: .continuous)
                .fill(Color.accentColor.opacity(0.16))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.block, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 1.5))
                .overlay(alignment: .topLeading) {
                    Text(Format.timeRange(EventLayout.date(on: days[di], minute: s), EventLayout.date(on: days[di], minute: e)))
                        .font(.subheadline).monospacedDigit().padding(6)
                }
                .frame(width: rect.width, height: rect.height)
                .popover(isPresented: $showCreatePopover, arrowEdge: .trailing) {
                    AreaPickerPopover(areas: selectableAreas) { area in create(in: area) }
                }
                .allowsHitTesting(false)
                .position(x: rect.midX, y: rect.midY)
                .zIndex(20)
        }
    }

    private func create(in area: Area) {
        guard case .creating(let di, let s, let e) = interaction, days.indices.contains(di) else { return }
        let start = EventLayout.date(on: days[di], minute: s)
        let end = EventLayout.date(on: days[di], minute: e)
        showCreatePopover = false
        interaction = nil
        Task {
            if let created = await google.createBlock(area: area, start: start, end: end) { selectedId = created.id }
            focused = true
        }
    }

    // MARK: Move & resize

    private func handleMove(_ p: PositionedEvent, dayIndex: Int, translation t: CGSize, ended: Bool, colW: CGFloat) {
        if !ended, !dragActive { dragActive = true; cancelled = false; selectedId = p.id; openId = nil; focused = true }
        guard !cancelled else { if ended { dragActive = false; cancelled = false }; return }

        let dur = p.event.end.timeIntervalSince(p.event.start) / 60
        let start = min(max(0, EventLayout.snap(p.startMinute + Double(t.height / hourHeight) * 60)), max(0, 1440 - dur))
        var di = dayIndex
        if days.count > 1 { di = min(max(0, dayIndex + Int((t.width / colW).rounded())), days.count - 1) }

        if !ended {
            interaction = .moving(id: p.id, dayIndex: di, start: start)
            return
        }
        interaction = nil
        dragActive = false
        let newStart = EventLayout.date(on: days[di], minute: start)
        guard abs(newStart.timeIntervalSince(p.event.start)) >= 60 else { return }
        Task { await google.updateBlock(event: p.event, start: newStart, end: newStart.addingTimeInterval(dur * 60), summary: nil) }
    }

    private func handleResize(_ p: PositionedEvent, dayIndex: Int, edge: ResizeEdge, dy: CGFloat, ended: Bool) {
        if !ended, !dragActive { dragActive = true; cancelled = false; selectedId = p.id; openId = nil; focused = true }
        guard !cancelled else { if ended { dragActive = false; cancelled = false }; return }

        let delta = Double(dy / hourHeight) * 60
        let minLen = Double(EventLayout.snapMinutes)
        var s = p.startMinute, e = p.endMinute
        if edge == .bottom { e = min(1440, max(s + minLen, EventLayout.snap(e + delta))) }
        else { s = max(0, min(e - minLen, EventLayout.snap(s + delta))) }

        if !ended {
            interaction = .resizing(id: p.id, dayIndex: dayIndex, start: s, end: e)
            return
        }
        interaction = nil
        dragActive = false
        let newStart = EventLayout.date(on: days[dayIndex], minute: s)
        let newEnd = EventLayout.date(on: days[dayIndex], minute: e)
        guard newStart != p.event.start || newEnd != p.event.end else { return }
        Task { await google.updateBlock(event: p.event, start: newStart, end: newEnd, summary: nil) }
    }

    private func cancelInteraction() {
        cancelled = true
        interaction = nil
        showCreatePopover = false
    }

    // MARK: Drops from the backlog

    private func dropOnBlock(_ ids: [String], _ p: PositionedEvent, area: Area?) {
        guard let area, !area.isClassesCalendar else { return }
        for id in ids {
            if let uuid = UUID(uuidString: id), let item = item(withId: uuid, in: store.context) {
                planItem(store, item: item, in: BlockRef(event: p.event, areaId: area.id))
            }
        }
        selectedId = p.id
    }

    private func dropOnEmpty(_ ids: [String], at point: CGPoint, colW: CGFloat) -> Bool {
        guard let id = ids.first, let uuid = UUID(uuidString: id), let item = item(withId: uuid, in: store.context),
              let area = selectableAreas.first(where: { $0.id == item.areaId }) else { return false }
        let i = dayIndex(forX: point.x, colW: colW)
        let start = min(1380, max(0, EventLayout.snapDown(minutes(forY: point.y))))
        let s = EventLayout.date(on: days[i], minute: start)
        Task {
            if let created = await google.createBlock(area: area, start: s, end: s.addingTimeInterval(3600)) {
                planItem(store, item: item, in: BlockRef(event: created, areaId: area.id))
                selectedId = created.id
            }
        }
        return true
    }

    // MARK: Delete

    private func deleteSelected() -> KeyPress.Result {
        guard let id = selectedId, let event = events.first(where: { $0.id == id }),
              let area = areaByCalendar[event.calendarId], !area.isClassesCalendar else { return .ignored }
        requestDelete(event)
        return .handled
    }

    private func requestDelete(_ event: CalendarEvent) {
        if let state = info.info(for: event)?.state, state != .unlogged {
            deleteCandidate = event
        } else {
            Task { await google.deleteBlock(event: event) }
        }
        selectedId = nil
    }

    // MARK: Now line & scrolling

    @ViewBuilder
    private func nowLine(colW: CGFloat) -> some View {
        if let i = days.firstIndex(where: { Calendar.current.isDateInToday($0) }) {
            TimelineView(.everyMinute) { ctx in
                let y = CGFloat(EventLayout.minuteOfDay(ctx.date, on: days[i])) / 60 * hourHeight
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Color.accentColor).frame(width: colW, height: 1).offset(x: CGFloat(i) * colW, y: y)
                    Circle().fill(Color.accentColor).frame(width: 8, height: 8).offset(x: CGFloat(i) * colW - 4, y: y - 3.5)
                }
                .frame(width: colW * CGFloat(days.count), height: hourHeight * 24, alignment: .topLeading)
            }
            .allowsHitTesting(false)
            .zIndex(15)
        }
    }

    private func scrollToDefault() {
        let cal = Calendar.current
        // Working hours by default; during the day, start just before now.
        var hour: Double = 7
        let now = Double(cal.component(.hour, from: .now))
        if days.contains(where: { cal.isDateInToday($0) }), (9...16).contains(Int(now)) { hour = now - 1.5 }
        Task { @MainActor in scroll.scrollTo(y: CGFloat(hour) * hourHeight) }
    }

    // MARK: Geometry

    private func minutes(forY y: CGFloat) -> Double { Double(max(0, min(hourHeight * 24, y)) / hourHeight) * 60 }
    private func dayIndex(forX x: CGFloat, colW: CGFloat) -> Int { min(max(0, Int(x / colW)), days.count - 1) }

    #if DEBUG
    /// `-CadenceDemoOpen detail|create|select` opens UI state for screenshots.
    private func debugOpen() async {
        guard !didDebugOpen, let what = DemoMode.arg("CadenceDemoOpen"), !events.isEmpty else { return }
        try? await Task.sleep(for: .seconds(1.5))
        // Loading more ranges re-runs this task; only the run that survives the sleep acts.
        guard !Task.isCancelled else { return }
        didDebugOpen = true
        let i = days.firstIndex { Calendar.current.isDateInToday($0) } ?? 0
        switch what {
        case "create":
            interaction = .creating(dayIndex: i, start: 10 * 60, end: 11 * 60)
            try? await Task.sleep(for: .milliseconds(300))
            showCreatePopover = true
        case "detail", "select":
            let target = events.first { e in
                guard let a = areaByCalendar[e.calendarId], !a.isClassesCalendar else { return false }
                return Calendar.current.isDate(e.start, inSameDayAs: days[i]) && info.info(for: e) != nil
            } ?? events.first { e in !(areaByCalendar[e.calendarId]?.isClassesCalendar ?? true) && Calendar.current.isDate(e.start, inSameDayAs: days[i]) }
            selectedId = target?.id
            if what == "detail" { openId = target?.id }
        default: break
        }
    }
    #endif
}

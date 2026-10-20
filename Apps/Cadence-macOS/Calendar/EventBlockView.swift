import SwiftUI
import CadenceCore

enum ResizeEdge { case top, bottom }

/// One block on the grid. All sizing comes from the canvas; gestures report back through closures.
struct EventBlockView: View {
    let positioned: PositionedEvent
    let area: Area?
    let info: BlockInfo?
    let size: CGSize
    let isSelected: Bool
    let isEditable: Bool
    let isDragging: Bool
    var previewRange: (start: Date, end: Date)?

    var onTap: () -> Void
    var onDoubleTap: () -> Void
    var onMove: (CGSize, Bool) -> Void           // translation, ended
    var onResize: (ResizeEdge, CGFloat, Bool) -> Void // edge, vertical translation, ended
    var onDrop: ([String]) -> Void

    @State private var hovering = false
    @State private var targeted = false

    private var event: CalendarEvent { positioned.event }
    private var color: AreaColor { area?.color ?? .classes }
    private var isClasses: Bool { area?.isClassesCalendar ?? true }
    private var state: BlockLogState { info?.state ?? .unlogged }
    private var isPastUnlogged: Bool { !isClasses && event.end < .now && state == .unlogged }
    /// A later overlapping block sits on top of this one's right side: show only the title.
    private var covered: Bool { positioned.laneCount > 1 && positioned.lane < positioned.laneCount - 1 }
    private var compact: Bool { size.height < 40 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Theme.Radius.block, style: .continuous)
                .fill(isClasses ? Color.secondary.opacity(hovering ? 0.20 : 0.13) : color.fill)
            if !isClasses {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color.base)
                    .frame(width: 3)
                    .padding(.vertical, 3)
                    .padding(.leading, 3)
            }
            content
                .padding(.leading, isClasses ? 8 : 11)
                .padding(.trailing, 6)
                .padding(.vertical, compact ? 1 : 4)
            if let symbol = stateSymbol {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color.base)
                    .padding(5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            if isEditable { resizeHandles }
        }
        .frame(width: size.width, height: size.height)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.block, style: .continuous)
                .strokeBorder(
                    targeted ? Color.accentColor : (isSelected ? color.base : (isPastUnlogged ? color.stroke : .clear)),
                    style: StrokeStyle(lineWidth: isSelected || targeted ? 1.5 : 1, dash: isPastUnlogged && !isSelected && !targeted ? [3, 3] : [])
                )
        )
        .brightness(hovering && !isClasses ? 0.04 : 0)
        .shadow(color: .black.opacity(isDragging ? 0.2 : 0), radius: isDragging ? 6 : 0, y: 2)
        .opacity(event.isCadenceBlock || !isClasses ? 1 : 0.95)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .pointerStyle(.link)
        .onTapGesture(count: 2, perform: onDoubleTap)
        .onTapGesture(perform: onTap)
        .gesture(isEditable ? moveGesture : nil)
        .dropDestination(for: String.self) { ids, _ in
            guard !isClasses else { return false }
            onDrop(ids)
            return true
        } isTargeted: { targeted = $0 && !isClasses }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(event.summary)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        let start = previewRange?.start ?? event.start
        let end = previewRange?.end ?? event.end
        // Narrow columns only have room for the start time.
        let range = size.width < 112 ? start.formatted(date: .omitted, time: .shortened) : Format.timeRange(start, end)
        if covered {
            Text(title).font(.callout.weight(.semibold)).lineLimit(1)
        } else if compact {
            HStack(spacing: 5) {
                Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                Text(range).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.8)
                Text(range).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
                let lines = max(0, Int((size.height - 8 - 34) / 14))
                if lines > 0, let titles = info?.itemTitles, !titles.isEmpty {
                    ForEach(titles.prefix(min(3, lines)), id: \.self) { t in
                        Text(t).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }

    private var title: String { event.summary.isEmpty ? (area?.name ?? "") : event.summary }

    private var stateSymbol: String? {
        guard !isClasses, state != .unlogged else { return nil }
        return OutcomeStyle.symbol(state)
    }

    private var accessibilityText: String {
        var text = "\(title), \(Format.timeRange(event.start, event.end))"
        if !isClasses, state != .unlogged { text += ", logged \(OutcomeStyle.title(state))" }
        return text
    }

    // MARK: Gestures

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { onMove($0.translation, false) }
            .onEnded { onMove($0.translation, true) }
    }

    private var resizeHandles: some View {
        VStack(spacing: 0) {
            handle(.top)
            Spacer(minLength: 0)
            handle(.bottom)
        }
    }

    private func handle(_ edge: ResizeEdge) -> some View {
        Color.clear
            .frame(height: 6)
            .contentShape(Rectangle())
            .pointerStyle(.frameResize(position: edge == .top ? .top : .bottom))
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { onResize(edge, $0.translation.height, false) }
                    .onEnded { onResize(edge, $0.translation.height, true) }
            )
    }
}

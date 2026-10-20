import SwiftUI

/// Seven day circles for the week containing `selection`. Tap to jump; swipe to change week.
struct WeekStrip: View {
    @Binding var selection: Date
    @ScaledMetric(relativeTo: .body) private var scaledCircle: CGFloat = 34
    /// Seven of these must always fit across the screen.
    private var circle: CGFloat { min(scaledCircle, 42) }
    /// Days that have Area blocks (shown with a small dot).
    var busyDays: Set<Date> = []

    private var cal: Calendar { .current }

    private var days: [Date] {
        let start = cal.dateInterval(of: .weekOfYear, for: selection)?.start ?? cal.startOfDay(for: selection)
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let isSelected = cal.isDate(day, inSameDayAs: selection)
                let isToday = cal.isDateInToday(day)
                Button {
                    withAnimation(Theme.snappy) { selection = day }
                } label: {
                    VStack(spacing: 4) {
                        Text(day, format: .dateTime.weekday(.narrow))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(day, format: .dateTime.day())
                            .font(.body.weight(isSelected ? .semibold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(isSelected ? Color.white : (isToday ? Color.accentColor : .primary))
                            .frame(width: circle, height: circle)
                            .background(Circle().fill(isSelected ? Color.accentColor : .clear))
                            .overlay(Circle().strokeBorder(isToday && !isSelected ? Color.accentColor : .clear, lineWidth: 1.5))
                        Circle()
                            .fill(busyDays.contains(cal.startOfDay(for: day)) ? Color.secondary.opacity(0.5) : .clear)
                            .frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { v in
                    guard abs(v.translation.width) > 60, abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                    let delta = v.translation.width < 0 ? 7 : -7
                    withAnimation(Theme.snappy) { selection = cal.date(byAdding: .day, value: delta, to: selection) ?? selection }
                }
        )
        .sensoryFeedback(.selection, trigger: selection)
    }
}

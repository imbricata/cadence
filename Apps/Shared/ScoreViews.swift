import SwiftUI
import CadenceCore

struct FormBar: View {
    let percent: Double?
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                if let percent {
                    Capsule()
                        .fill(percent >= 100 ? Color.accentColor : Color.secondary.opacity(0.6))
                        .frame(width: max(0, min(1, percent / 100)) * geo.size.width)
                }
            }
        }
        .frame(height: 6)
    }
}

struct FollowThroughChart: View {
    let days: [DayFollowThrough]
    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(days, id: \.date) { day in
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(day.planned > 0 ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: 14, height: height(for: day))
                    Text(day.date, format: .dateTime.weekday(.narrow))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func height(for day: DayFollowThrough) -> CGFloat {
        guard day.planned > 0 else { return 4 }
        let ratio = min(1, day.loggedWeight / Double(day.planned))
        return max(4, ratio * 40)
    }
}

struct FormLabel: View {
    let percent: Double?
    var body: some View {
        if let percent {
            Text("\(Int(percent.rounded()))%")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(percent >= 100 ? Color.primary : Color.secondary)
        } else {
            Text("Calibrating")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
import SwiftUI
import CadenceCore

// MARK: - Area bits

struct AreaDot: View {
    let colorHex: String
    var size: CGFloat = 10
    var body: some View {
        Circle().fill(AreaColor(colorHex).base).frame(width: size, height: size)
    }
}

/// Toggle capsule with a colour dot. Wraps naturally inside `ChipFlow`.
struct AreaChip: View {
    let title: String
    let colorHex: String
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.xs + 2) {
                AreaDot(colorHex: colorHex, size: 8)
                Text(title).lineLimit(1)
            }
            .font(.callout)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s - 1)
            .background(Capsule().fill(isOn ? AreaColor(colorHex).fill : Color.secondary.opacity(0.10)))
            .overlay(Capsule().strokeBorder(isOn ? AreaColor(colorHex).stroke : .clear, lineWidth: 1))
            .foregroundStyle(isOn ? Color.primary : Color.secondary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isOn)
    }
}

/// Lays out children left to right and wraps to new rows (for chips).
struct ChipFlow: Layout {
    var spacing: CGFloat = Theme.Space.s

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (i, origin) in result.origins.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}

// MARK: - Logging controls

enum OutcomeStyle {
    static func symbol(_ state: BlockLogState) -> String {
        switch state {
        case .full: return "checkmark"
        case .easy: return "circle.lefthalf.filled"
        case .skipped: return "xmark"
        case .unlogged: return "circle.dashed"
        }
    }
    static func symbol(_ outcome: LogOutcome) -> String {
        switch outcome {
        case .full: return "checkmark"
        case .easy: return "circle.lefthalf.filled"
        case .skipped: return "xmark"
        case .planned: return "circle.dashed"
        }
    }
    static func title(_ state: BlockLogState) -> String {
        switch state {
        case .full: return "Full"
        case .easy: return "Easy"
        case .skipped: return "Skipped"
        case .unlogged: return "Not yet"
        }
    }
}

/// Not yet / Full / Easy / Skipped as one segmented control with symbols.
struct OutcomePicker: View {
    @Binding var selection: BlockLogState

    var body: some View {
        Picker("Outcome", selection: $selection) {
            ForEach([BlockLogState.unlogged, .full, .easy, .skipped], id: \.self) { s in
                Label(OutcomeStyle.title(s), systemImage: OutcomeStyle.symbol(s)).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// "45 min" with +/- and (typing) support.
struct MinutesField: View {
    @Binding var minutes: Int
    var step = 5
    var range = 0...600

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            TextField("", value: $minutes, format: .number)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 44)
                #if os(macOS)
                .textFieldStyle(.roundedBorder)
                #endif
                .accessibilityLabel("Minutes")
            Text("min").foregroundStyle(.secondary)
            Stepper("Minutes", value: $minutes, in: range, step: step).labelsHidden()
        }
    }
}

// MARK: - Text & states

enum Format {
    /// "1 h 30 min", "45 min", "2 h".
    static func duration(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// "63 h", "1.5 h", "45 min".
    static func hours(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = Double(minutes) / 60
        return h >= 10 ? "\(Int(h.rounded())) h" : String(format: "%.1f h", h)
    }

    static func timeRange(_ start: Date, _ end: Date) -> String {
        "\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"
    }
}

struct PercentText: View {
    let value: Double?
    var body: some View {
        if let value {
            Text("\(Int(value.rounded()))%").monospacedDigit()
        } else {
            Text("Calibrating").foregroundStyle(.secondary)
        }
    }
}

/// One calm line, centred. The only empty state the app uses inline.
struct EmptyLine: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(Theme.Space.xl)
    }
}

// MARK: - Banner & toast

/// Reconnect / offline notice shown above the main content.
struct StatusBanner: View {
    @Environment(GoogleService.self) private var google

    var body: some View {
        switch google.connectionState {
        case .needsReconnect:
            row(icon: "exclamationmark.circle", text: "Google disconnected.", button: "Reconnect") {
                Task { await google.signIn() }
            }
        case .offline:
            row(icon: "wifi.slash", text: "You're offline. Showing saved data.", button: nil, action: {})
        case .connected, .disconnected:
            EmptyView()
        }
    }

    private func row(icon: String, text: String, button: String?, action: @escaping () -> Void) -> some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: icon).foregroundStyle(.orange)
            Text(text).font(.callout)
            Spacer()
            if let button { Button(button, action: action).buttonStyle(.bordered).controlSize(.small) }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Shows `google.message` as a toast at the bottom and clears it after a few seconds.
struct ToastHost: ViewModifier {
    @Environment(GoogleService.self) private var google

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let m = google.message {
                    HStack(spacing: Theme.Space.m) {
                        Text(m.text).font(.callout)
                        if let title = m.actionTitle, let action = m.action {
                            Button(title) { action(); google.message = nil }
                                .buttonStyle(.plain)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.vertical, Theme.Space.m)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                    .padding(.bottom, Theme.Space.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(m.id)
                    .task(id: m.id) {
                        try? await Task.sleep(for: .seconds(m.actionTitle == nil ? 3 : 6))
                        if google.message?.id == m.id { google.message = nil }
                    }
                }
            }
            .animation(Theme.snappy, value: google.message?.id)
    }
}

extension View {
    func toastHost() -> some View { modifier(ToastHost()) }

    /// Puts the reconnect / offline banner above this screen's content.
    func statusBanner() -> some View {
        safeAreaInset(edge: .top, spacing: 0) { StatusBanner() }
    }
}

// MARK: - Settings access

private struct OpenSettingsKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /// iOS: presents the Settings sheet from any tab.
    var openSettings: () -> Void {
        get { self[OpenSettingsKey.self] }
        set { self[OpenSettingsKey.self] = newValue }
    }
}

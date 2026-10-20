import SwiftUI
import SwiftData
import CadenceCore

struct CreateSlot: Identifiable {
    let id = UUID()
    var day: Date
    var startMinute: Double
}

/// Area, start, duration, Create. Opens at the tapped time with the last-used Area selected.
struct QuickCreateSheet: View {
    @Environment(GoogleService.self) private var google
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Area.sortOrder) private var allAreas: [Area]
    @AppStorage("quickCreate.lastArea") private var lastAreaRaw = ""

    let slot: CreateSlot

    @State private var areaId: UUID?
    @State private var start: Date
    @State private var duration = 60
    @State private var creating = false

    private let durations = [30, 45, 60, 90, 120]

    init(slot: CreateSlot) {
        self.slot = slot
        _start = State(initialValue: EventLayout.date(on: slot.day, minute: slot.startMinute))
    }

    private var areas: [Area] { allAreas.filter { !$0.isDeleted && !$0.isArchived && !$0.isClassesCalendar } }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Text(slot.day, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Area").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Space.s) {
                            ForEach(areas) { area in
                                AreaChip(title: area.name, colorHex: area.colorHex, isOn: areaId == area.id) { areaId = area.id }
                            }
                        }
                    }
                }

                DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)

                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Duration").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(spacing: Theme.Space.s) {
                        ForEach(durations, id: \.self) { d in
                            Button { duration = d } label: {
                                Text(d < 60 ? "\(d)m" : (d % 60 == 0 ? "\(d / 60)h" : "\(d / 60).5h"))
                                    .font(.callout.monospacedDigit())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(duration == d ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10)))
                                    .overlay(Capsule().strokeBorder(duration == d ? Color.accentColor : .clear, lineWidth: 1))
                                    .foregroundStyle(duration == d ? Color.primary : .secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(d) minutes")
                            .accessibilityAddTraits(duration == d ? .isSelected : [])
                        }
                    }
                    .sensoryFeedback(.selection, trigger: duration)
                }

                Spacer(minLength: 0)

                Button { Task { await create() } } label: {
                    Text("Create").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(areaId == nil || creating)
            }
            .padding(Theme.Space.l)
            .navigationTitle("New block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                if areaId == nil { areaId = areas.first { $0.id.uuidString == lastAreaRaw }?.id ?? areas.first?.id }
            }
        }
        .presentationDetents([.medium])
    }

    private func create() async {
        guard let area = areas.first(where: { $0.id == areaId }) else { return }
        creating = true
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute], from: start)
        let begin = cal.date(bySettingHour: t.hour ?? 9, minute: t.minute ?? 0, second: 0, of: slot.day) ?? start
        lastAreaRaw = area.id.uuidString
        await google.createBlock(area: area, start: begin, end: begin.addingTimeInterval(Double(duration) * 60))
        dismiss()
    }
}

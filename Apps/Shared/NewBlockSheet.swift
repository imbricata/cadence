import SwiftUI
import SwiftData
import CadenceCore

struct NewBlockSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(GoogleService.self) private var google
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Area.sortOrder) private var areas: [Area]

    @State private var selectedAreaId: UUID?
    @State private var date: Date
    @State private var startTime: Date
    @State private var durationMinutes: Int = 60

    private var selectableAreas: [Area] {
        areas.filter { !$0.isDeleted && !$0.isArchived && !$0.isClassesCalendar }
    }

    init(initialDate: Date = .now, initialStart: Date = .now) {
        _date = State(initialValue: initialDate)
        _startTime = State(initialValue: initialStart)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Area") {
                    Picker("Area", selection: $selectedAreaId) {
                        Text("Choose…").tag(UUID?.none)
                        ForEach(selectableAreas) { area in
                            HStack {
                                AreaDot(colorHex: area.colorHex)
                                Text(area.name)
                            }
                            .tag(Optional(area.id))
                        }
                    }
                }
                Section("When") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                    Picker("Duration", selection: $durationMinutes) {
                        Text("30 min").tag(30)
                        Text("45 min").tag(45)
                        Text("1 hour").tag(60)
                        Text("1.5 hours").tag(90)
                        Text("2 hours").tag(120)
                    }
                }
            }
            .navigationTitle("New block")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await save() } }
                        .disabled(selectedAreaId == nil)
                }
            }
            .onAppear {
                if selectedAreaId == nil { selectedAreaId = selectableAreas.first?.id }
            }
        }
    }

    private func save() async {
        guard let areaId = selectedAreaId, let area = selectableAreas.first(where: { $0.id == areaId }) else { return }
        let start = combine(date: date, time: startTime)
        let end = start.addingTimeInterval(Double(durationMinutes) * 60)
        await google.createBlock(area: area, start: start, end: end)
        dismiss()
    }

    private func combine(date: Date, time: Date) -> Date {
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(bySettingHour: t.hour ?? 9, minute: t.minute ?? 0, second: 0, of: date) ?? date
    }
}
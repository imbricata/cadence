import SwiftUI
import CadenceCore

let symbolChoices: [String] = [
    "circle", "heart", "book", "dumbbell", "graduationcap", "briefcase",
    "paintbrush", "laptopcomputer", "music.note", "fork.knife", "house", "leaf",
    "figure.walk", "figure.run", "bicycle", "pencil", "gift", "waveform",
    "camera", "gamecontroller", "stethoscope", "airplane", "brain.head.profile", "moon",
    "sun.max", "cart", "wrench.and.screwdriver", "theatermasks", "globe", "banknote",
    "person.2", "pawprint", "guitars", "star"
]

struct AreaEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(GoogleService.self) private var google
    @Environment(\.dismiss) private var dismiss
    let area: Area?

    enum CalendarChoice: Hashable { case create, existing }

    @State private var name: String
    @State private var colorHex: String
    @State private var symbolName: String
    @State private var choice: CalendarChoice = .create
    @State private var calendars: [GoogleCalendar] = []
    @State private var selectedCalendarId = ""
    @State private var confirmDelete = false

    init(area: Area?) {
        self.area = area
        _name = State(initialValue: area?.name ?? "")
        _colorHex = State(initialValue: area?.colorHex ?? AreaPalette.all.first!)
        _symbolName = State(initialValue: area?.symbolName ?? "circle")
        _selectedCalendarId = State(initialValue: area?.googleCalendarId ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                }
                Section("Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))], spacing: Theme.Space.m) {
                        ForEach(AreaPalette.all, id: \.self) { hex in
                            Button { colorHex = hex } label: {
                                ZStack {
                                    Circle().fill(AreaColor(hex).base).frame(width: 28, height: 28)
                                    if colorHex == hex {
                                        Circle().strokeBorder(Color.primary, lineWidth: 2).frame(width: 36, height: 36)
                                    }
                                }
                                .frame(width: 40, height: 40)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Color")
                            .accessibilityAddTraits(colorHex == hex ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, Theme.Space.xs)
                }
                Section("Symbol") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))], spacing: Theme.Space.s) {
                        ForEach(symbolChoices, id: \.self) { sym in
                            Button { symbolName = sym } label: {
                                Image(systemName: sym)
                                    .font(.title3)
                                    .foregroundStyle(symbolName == sym ? AreaColor(colorHex).base : Color.secondary)
                                    .frame(width: 40, height: 40)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(symbolName == sym ? AreaColor(colorHex).fill : .clear))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(sym)
                            .accessibilityAddTraits(symbolName == sym ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, Theme.Space.xs)
                }

                if google.isAuthorized, area?.isClassesCalendar != true { calendarSection }

                if let area {
                    Section {
                        Button(area.isArchived ? "Unarchive" : "Archive") {
                            updateArea(store, area, isArchived: !area.isArchived)
                            dismiss()
                        }
                        Button("Delete…", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(area == nil ? "New Area" : "Edit Area")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task {
                if google.isAuthorized, let list = try? await google.listGoogleCalendars() { calendars = list }
            }
            .confirmationDialog("Delete \(area?.name ?? "area")?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Area") { remove(deleteCalendar: false) }
                if area?.googleCalendarId.isEmpty == false {
                    Button("Delete Area and Google Calendar", role: .destructive) { remove(deleteCalendar: true) }
                }
            } message: {
                Text("Its items disappear from the app. By default the Google calendar is kept.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 560)
        #endif
    }

    @ViewBuilder
    private var calendarSection: some View {
        Section {
            if area == nil {
                Picker("Calendar", selection: $choice) {
                    Text("Create a new calendar").tag(CalendarChoice.create)
                    Text("Link an existing calendar").tag(CalendarChoice.existing)
                }
                .pickerStyle(.menu)
            }
            if area != nil || choice == .existing {
                Picker(area == nil ? "Calendar" : "Linked to", selection: $selectedCalendarId) {
                    if area?.googleCalendarId.isEmpty ?? true { Text("None").tag("") }
                    ForEach(calendars) { Text($0.summary ?? $0.id).tag($0.id) }
                }
            }
        } header: {
            Text("Google Calendar")
        } footer: {
            Text(area == nil && choice == .create ? "Blocks for this area live in a calendar named after it." : "Blocks for this area are read from and written to this calendar.")
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let area {
            updateArea(store, area, name: trimmed, colorHex: colorHex, symbolName: symbolName)
            if let cal = calendars.first(where: { $0.id == selectedCalendarId }), cal.id != area.googleCalendarId {
                google.linkArea(area, to: cal)
            }
            Task { await google.applyAreaAppearance(area) }
        } else if choice == .existing, let cal = calendars.first(where: { $0.id == selectedCalendarId }) {
            createArea(store, name: trimmed, colorHex: colorHex, symbolName: symbolName, calendarId: cal.id)
            Task { await google.refreshVisible(force: true) }
        } else {
            let new = createArea(store, name: trimmed, colorHex: colorHex, symbolName: symbolName)
            Task { await google.ensureCalendar(for: new) }
        }
        dismiss()
    }

    private func remove(deleteCalendar: Bool) {
        guard let area else { return }
        Task { await google.removeArea(area, deleteCalendar: deleteCalendar) }
        dismiss()
    }
}

import SwiftUI
import SwiftData
import CadenceCore

struct GoogleSettingsSection: View {
    @Environment(GoogleService.self) private var google
    @Query(sort: \Area.sortOrder) private var areas: [Area]
    @State private var calendars: [GoogleCalendar] = []
    @State private var selectedCalendarId: String = ""

    private var classes: Area? { areas.first { !$0.isDeleted && $0.isClassesCalendar } }

    var body: some View {
        Section("Google") {
            if !google.isAuthorized {
                Button("Connect Google Calendar") { Task { await google.signIn() } }
            } else {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button("Sign out", role: .destructive) { google.signOut() }
            }
            if google.needsReconnect {
                Button("Reconnect Google") { Task { await google.signIn() } }
                    .foregroundStyle(.orange)
            }
        }

        if google.isAuthorized {
            Section("Classes calendar") {
                if let classes {
                    Label(classes.name, systemImage: "graduationcap")
                } else {
                    Picker("Classes calendar", selection: $selectedCalendarId) {
                        Text("Select…").tag("")
                        ForEach(calendars) { cal in
                            Text(cal.summary ?? cal.id).tag(cal.id)
                        }
                    }
                    .onAppear { loadCalendars() }
                    .onChange(of: selectedCalendarId) { _, newValue in
                        if let cal = calendars.first(where: { $0.id == newValue }) {
                            google.linkClassesCalendar(cal)
                        }
                    }
                }
            }

            Section("Sync") {
                if let last = google.lastSyncAt {
                    LabeledContent("Last sync", value: last.formatted(.relative(presentation: .named)))
                }
                LabeledContent("Events loaded", value: "\(google.lastEventCount)")
                    .monospacedDigit()
                if let err = google.lastEventError {
                    Text(err).font(.footnote).foregroundStyle(.red)
                }
                Button {
                    Task { await google.syncNow() }
                } label: {
                    if google.isSyncing { ProgressView() } else { Text("Sync now") }
                }
                .disabled(google.isSyncing)
            }
        }
    }

    private func loadCalendars() {
        Task {
            if let cals = try? await google.listGoogleCalendars() { calendars = cals }
        }
    }
}

/// Calm empty-state prompt shown on the Today/Plan screen when Google isn't connected.
struct ConnectGooglePlaceholder: View {
    var body: some View {
        ContentUnavailableView {
            Label("Connect Google Calendar", systemImage: "calendar.badge.plus")
        } description: {
            Text("Connect Google to link your college calendar and begin planning your days.")
        }
    }
}
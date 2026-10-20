import SwiftUI
import SwiftData
import CadenceCore

// MARK: - Google account

struct AccountSection: View {
    @Environment(GoogleService.self) private var google

    var body: some View {
        Section("Google") {
            switch google.connectionState {
            case .disconnected:
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Connect Google to see your calendars and keep your phone and Mac in sync.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Connect Google") { Task { await google.signIn() } }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, Theme.Space.xs)
            case .needsReconnect, .offline, .connected:
                LabeledContent("Account", value: google.accountEmail ?? "Connected")
                if google.connectionState == .needsReconnect {
                    Button("Reconnect") { Task { await google.signIn() } }
                }
                Button("Disconnect", role: .destructive) { google.signOut() }
            }
        }
    }
}

// MARK: - Classes

struct ClassesSection: View {
    @Query(sort: \Area.sortOrder) private var areas: [Area]
    @State private var showSheet = false

    private var classes: Area? { areas.first { !$0.isDeleted && $0.isClassesCalendar } }

    var body: some View {
        Section("Classes") {
            if let classes {
                LabeledContent("Calendar", value: classes.name)
                Text(classes.googleCalendarId.hasPrefix("http") ? "From a calendar link. Updates automatically." : "From Google Calendar.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Your timetable, shown read-only on Today and Plan.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button(classes == nil ? "Set Up…" : "Change…") { showSheet = true }
        }
        .sheet(isPresented: $showSheet) { ClassesSourceSheet() }
    }
}

struct ClassesSourceSheet: View {
    @Environment(GoogleService.self) private var google
    @Environment(\.dismiss) private var dismiss

    enum Source: String, CaseIterable { case google = "Google Calendar", link = "Calendar link" }

    @State private var source: Source = .link
    @State private var calendars: [GoogleCalendar] = []
    @State private var selectedId = ""
    @State private var link = ""
    @State private var check: String?
    @State private var checking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Source", selection: $source) {
                        ForEach(Source.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                switch source {
                case .google:
                    Section("Calendar") {
                        if !google.isAuthorized {
                            Text("Connect Google first.").foregroundStyle(.secondary)
                        } else if calendars.isEmpty {
                            ProgressView()
                        } else {
                            Picker("Calendar", selection: $selectedId) {
                                Text("Choose…").tag("")
                                ForEach(calendars) { Text($0.summary ?? $0.id).tag($0.id) }
                            }
                            #if os(macOS)
                            .pickerStyle(.menu)
                            #endif
                        }
                    }
                case .link:
                    Section {
                        TextField("https://…/calendar.ics", text: $link)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif
                        HStack {
                            Button("Check link") { Task { await validate() } }
                                .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty || checking)
                            if checking { ProgressView().controlSize(.small) }
                            if let check { Text(check).font(.callout).foregroundStyle(.secondary) }
                        }
                    } header: {
                        Text("Calendar link")
                    } footer: {
                        Text("Paste the .ics link from your university (for example Blackboard). It refreshes by itself.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Classes")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Use") { apply() }.disabled(!canApply) }
            }
            .task {
                if google.isAuthorized, let list = try? await google.listGoogleCalendars() { calendars = list }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 300)
        #endif
    }

    private var canApply: Bool {
        source == .google ? !selectedId.isEmpty : !link.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func apply() {
        if source == .google, let cal = calendars.first(where: { $0.id == selectedId }) {
            google.linkClassesCalendar(cal)
        } else if source == .link {
            google.linkClassesICS(link)
        }
        dismiss()
    }

    private func validate() async {
        checking = true
        defer { checking = false }
        do {
            let n = try await google.validateICS(link)
            check = n == 0 ? "No events found yet." : "Found \(n) events."
        } catch {
            check = (error as? LocalizedError)?.errorDescription ?? "Couldn't read that link."
        }
    }
}

// MARK: - Sync

struct SyncSection: View {
    @Environment(GoogleService.self) private var google

    var body: some View {
        if google.isAuthorized {
            Section("Sync") {
                LabeledContent("Last synced") {
                    if let last = google.lastSyncAt {
                        Text(last, format: .relative(presentation: .named))
                    } else {
                        Text("Never")
                    }
                }
                Button {
                    Task { await google.syncNow(); await google.refreshVisible() }
                } label: {
                    HStack {
                        Text("Sync Now")
                        if google.isSyncing { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(google.isSyncing)
            }
        }
    }
}

// MARK: - AI sorting

struct AISortingSection: View {
    @Environment(InboxService.self) private var inbox

    @State private var key = ""
    @State private var model = ""
    @State private var cap = 1.0
    @State private var keySaved = false

    var body: some View {
        Section {
            SecureField("OpenRouter API key", text: $key)
                .onSubmit(saveKey)
            HStack {
                Button("Save Key", action: saveKey)
                    .disabled(key == inbox.currentKey)
                if keySaved || (inbox.hasKey && key == inbox.currentKey) {
                    Label("Key saved", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }
            TextField("Model", text: $model)
                .autocorrectionDisabled()
                .onSubmit { inbox.setModel(model) }
        } header: {
            Text("OpenRouter")
        } footer: {
            Text("Notes you send to the Inbox are sorted into tasks and activities with this model.")
        }
        .onAppear {
            key = inbox.currentKey
            model = inbox.model
            cap = inbox.monthlyCapUSD
        }

        Section("This month") {
            LabeledContent("Estimated cost") {
                Text("\(inbox.monthCostUSD, format: .currency(code: "USD").precision(.fractionLength(3))) of \(cap, format: .currency(code: "USD").precision(.fractionLength(2)))")
                    .monospacedDigit()
            }
            Stepper(value: $cap, in: 0.25...20, step: 0.25) {
                Text("Monthly cap")
            }
            .onChange(of: cap) { _, v in inbox.setCap(v) }
            if inbox.isOverCap {
                Label("Cap reached. Sorting is paused until next month or until you raise it.", systemImage: "pause.circle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func saveKey() {
        inbox.setKey(key.trimmingCharacters(in: .whitespacesAndNewlines))
        keySaved = true
        Task { await inbox.processPending() }
    }
}

// MARK: - Advanced

struct AdvancedSection: View {
    @Environment(GoogleService.self) private var google

    var body: some View {
        Section("Advanced") {
            DisclosureGroup("Diagnostics") {
                LabeledContent("Events cached", value: "\(google.lastEventCount)").monospacedDigit()
                LabeledContent("Connection", value: String(describing: google.connectionState))
                if let e = google.lastEventError { diagnostic("Calendar", e) }
                if let e = google.lastSyncError { diagnostic("Sync", e) }
                Button("Repair calendar links") { Task { await google.repairCalendarLinks() } }
                    .disabled(!google.isAuthorized)
            }
        }
    }

    private func diagnostic(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.footnote.weight(.semibold))
            Text(text).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}

struct AboutSection: View {
    var body: some View {
        Section("About") {
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
        }
    }
}

/// Calm prompt for the Today / Plan area when Google isn't connected. Onboarding builds on this.
struct ConnectGooglePlaceholder: View {
    @Environment(GoogleService.self) private var google

    var body: some View {
        ContentUnavailableView {
            Label("Connect Google Calendar", systemImage: "calendar.badge.plus")
        } description: {
            Text("Connect Google to see your classes and plan your days.")
        } actions: {
            Button("Connect Google") { Task { await google.signIn() } }
                .buttonStyle(.borderedProminent)
        }
    }
}

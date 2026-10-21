import SwiftUI
import SwiftData
import CadenceCore

/// The Cadence mark: four rounded bars, drawn in the accent colour.
struct BrandMark: View {
    var height: CGFloat = 60
    var body: some View {
        let u = height / 60
        HStack(alignment: .bottom, spacing: 8 * u) {
            ForEach([30.0, 46, 60, 44], id: \.self) { h in
                RoundedRectangle(cornerRadius: 7 * u, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: 14 * u, height: h * u)
            }
        }
        .accessibilityHidden(true)
    }
}

/// First run: connect Google, restore from Drive (second device) or set up Classes and a first Area.
struct OnboardingView: View {
    @Environment(GoogleService.self) private var google
    @Query(sort: \Area.sortOrder) private var areas: [Area]

    enum Step { case welcome, restored, classes, areas }

    @State private var step: Step = .welcome
    @State private var connecting = false
    @State private var showClasses = false
    @State private var showNewArea = false

    var onFinish: () -> Void

    private var userAreas: [Area] { areas.filter { !$0.isDeleted && !$0.isClassesCalendar && !$0.isArchived } }
    private var classes: Area? { areas.first { !$0.isDeleted && $0.isClassesCalendar } }

    var body: some View {
        VStack(spacing: Theme.Space.xl) {
            Spacer(minLength: Theme.Space.l)
            BrandMark()
            Group {
                switch step {
                case .welcome: welcome
                case .restored: restored
                case .classes: classesStep
                case .areas: areasStep
                }
            }
            .multilineTextAlignment(.center)
            .transition(.opacity)
            Spacer(minLength: Theme.Space.l)
            if step != .restored {
                Button("Skip for now", action: skip)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .padding(Theme.Space.xxl)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Theme.snappy, value: step)
        .sheet(isPresented: $showClasses) { ClassesSourceSheet() }
        .sheet(isPresented: $showNewArea) { AreaEditorView(area: nil) }
        .toastHost()
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 520)
        #endif
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: Theme.Space.l) {
            Text("Cadence").font(.largeTitle.weight(.semibold))
            Text("Plan your days around the areas of your life.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button {
                Task { await connect() }
            } label: {
                HStack {
                    if connecting { ProgressView().controlSize(.small) }
                    Text("Connect Google").frame(minWidth: 160)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(connecting)
            Text("Used for your calendars and for private sync between your devices. Nothing else.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    private var restored: some View {
        VStack(spacing: Theme.Space.l) {
            Text("Welcome back").font(.largeTitle.weight(.semibold))
            Text("Your areas and data were restored.").font(.title3).foregroundStyle(.secondary)
            Button("Done", action: onFinish)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private var classesStep: some View {
        VStack(spacing: Theme.Space.l) {
            Text("Your classes").font(.title.weight(.semibold))
            Text("Add your timetable from a calendar link or a Google calendar. It stays read-only.")
                .font(.body)
                .foregroundStyle(.secondary)
            if let classes {
                Label("\(classes.name) is set", systemImage: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
            }
            Button(classes == nil ? "Set Up Classes…" : "Change…") { showClasses = true }
                .controlSize(.large)
            Button("Continue") { step = .areas }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(classes == nil)
        }
    }

    private var areasStep: some View {
        VStack(spacing: Theme.Space.l) {
            Text("Your areas").font(.title.weight(.semibold))
            Text("The parts of life you want to give time to: Fitness, Work, a language. Each gets its own calendar.")
                .font(.body)
                .foregroundStyle(.secondary)
            if !userAreas.isEmpty {
                ChipFlow {
                    ForEach(userAreas) { AreaChip(title: $0.name, colorHex: $0.colorHex, isOn: true) {} }
                }
            }
            Button(userAreas.isEmpty ? "Add an Area…" : "Add Another…") { showNewArea = true }
                .controlSize(.large)
            Button("Done", action: onFinish)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(userAreas.isEmpty)
        }
    }

    // MARK: Actions

    private func connect() async {
        connecting = true
        defer { connecting = false }
        await google.signIn()
        guard google.isAuthorized else { return }
        step = userAreas.isEmpty ? .classes : .restored
    }

    private func skip() {
        switch step {
        case .welcome, .areas, .restored: onFinish()
        case .classes: step = .areas
        }
    }
}

/// Decides when onboarding shows: not skipped before, and there are no Areas yet.
struct OnboardingGate: ViewModifier {
    @Query private var areas: [Area]
    @AppStorage("onboarding.dismissed") private var dismissed = false
    @State private var forced = false

    private var hasAreas: Bool { areas.contains { !$0.isDeleted && !$0.isClassesCalendar } }
    private var shouldShow: Bool { forced || (!dismissed && !hasAreas) }

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(isPresented: binding) { OnboardingView(onFinish: finish) }
            #if DEBUG
            .task { forced = DemoMode.arg("CadenceOnboarding") != nil }
            #endif
        #else
        content.sheet(isPresented: binding) { OnboardingView(onFinish: finish) }
            #if DEBUG
            .task { forced = DemoMode.arg("CadenceOnboarding") != nil }
            #endif
        #endif
    }

    private var binding: Binding<Bool> {
        Binding(get: { shouldShow }, set: { if !$0 { finish() } })
    }

    private func finish() {
        dismissed = true
        forced = false
    }
}

extension View {
    func onboarding() -> some View { modifier(OnboardingGate()) }
}

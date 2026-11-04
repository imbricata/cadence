#if DEBUG
import SwiftUI
import SwiftData
import CadenceCore

/// Realistic fixtures for screenshots and UI work. Enabled with the launch argument `-CadenceDemo YES`.
/// Nothing here touches Google, the Keychain or the real store.
enum DemoMode {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "CadenceDemo") }
    /// Other DEBUG launch arguments, e.g. `-CadenceTab inbox`, `-CadenceSection plan`.
    static func arg(_ name: String) -> String? { UserDefaults.standard.string(forKey: name) }
    static var colorScheme: ColorScheme? {
        switch arg("CadenceAppearance") {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    struct Spec { let key: String; let name: String; let hex: String; let symbol: String }
    static let specs: [Spec] = [
        .init(key: "fitness", name: "Fitness", hex: "#C46A5A", symbol: "dumbbell"),
        .init(key: "spanish", name: "Spanish", hex: "#6A93B8", symbol: "book"),
        .init(key: "work", name: "Work", hex: "#5C9B96", symbol: "briefcase"),
        .init(key: "music", name: "Music", hex: "#9C82B0", symbol: "music.note"),
        .init(key: "home", name: "Home", hex: "#7A9C6A", symbol: "house")
    ]
    static func calendarId(_ key: String) -> String { "demo-\(key)" }

    // MARK: Schedule (shared by the fake calendar and the seeded logs)

    struct Block { let key: String; let start: Date; let minutes: Int; var id: String { "demo-\(key)-\(Int(start.timeIntervalSince1970))" } }

    static func blocks(on day: Date) -> [Block] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let wd = cal.component(.weekday, from: day) // 1 = Sunday
        func at(_ hours: Double) -> Date { start.addingTimeInterval(hours * 3600) }
        var out: [Block] = []
        if [2, 4, 6].contains(wd) { out.append(Block(key: "fitness", start: at(7), minutes: 60)) }
        if wd == 7 { out.append(Block(key: "fitness", start: at(10), minutes: 90)) }
        if [3, 5].contains(wd) { out.append(Block(key: "work", start: at(9), minutes: 120)) }
        if [2, 4, 6].contains(wd) { out.append(Block(key: "work", start: at(14), minutes: 120)) }
        if [3, 5].contains(wd) { out.append(Block(key: "spanish", start: at(18), minutes: 60)) }
        if wd == 1 { out.append(Block(key: "spanish", start: at(11), minutes: 45)) }
        if [2, 5].contains(wd) { out.append(Block(key: "music", start: at(18.5), minutes: 60)) }
        if wd == 7 { out.append(Block(key: "home", start: at(15), minutes: 90)) }
        return out
    }

    static func classEvents(on day: Date) -> [CalendarEvent] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let wd = cal.component(.weekday, from: day)
        let id = Int(start.timeIntervalSince1970)
        var out: [CalendarEvent] = []
        func ev(_ name: String, _ h: Double, _ minutes: Int) -> CalendarEvent {
            let s = start.addingTimeInterval(h * 3600)
            return CalendarEvent(id: "demo-class-\(name)-\(id)", summary: name, start: s, end: s.addingTimeInterval(Double(minutes) * 60), calendarId: calendarId("classes"))
        }
        if [2, 4, 6].contains(wd) { out.append(ev("Microeconomics", 10.5, 90)) }
        if [3, 5].contains(wd) { out.append(ev("Statistics", 12.5, 90)) }
        let offset = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: start).day ?? 0
        if offset == 0 {
            let s = start.addingTimeInterval(17 * 3600)
            out.append(CalendarEvent(id: "demo-deadline-ps-\(id)", summary: "Problem set due", start: s, end: s, calendarId: calendarId("classes")))
        }
        if offset == 1 {
            let s = start.addingTimeInterval(23.98 * 3600)
            out.append(CalendarEvent(id: "demo-deadline-essay-\(id)", summary: "Essay due", start: s, end: s, calendarId: calendarId("classes")))
        }
        if offset == 2 {
            out.append(CalendarEvent(id: "demo-allday-\(id)", summary: "Campus closed", start: start, end: cal.date(byAdding: .day, value: 1, to: start)!, calendarId: calendarId("classes"), isAllDay: true))
        }
        return out
    }

    // MARK: Services

    @MainActor
    static func makeServices() -> AppServices {
        let store = try! AppStore.inMemory()
        seed(store)
        let google = GoogleService(store: store, eventSource: DemoEventSource(), isDemo: true)
        let inbox = InboxService(store: store, keyProvider: { nil })
        return AppServices(store: store, google: google, inbox: inbox, insights: InsightsModel(store: store, events: google.eventStore))
    }

    @MainActor
    static func seed(_ store: AppStore) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today)! }

        var areas: [String: Area] = [:]
        for (i, s) in specs.enumerated() {
            let a = createArea(store, name: s.name, colorHex: s.hex, symbolName: s.symbol, calendarId: calendarId(s.key))
            a.sortOrder = i
            a.createdAt = day(s.key == "home" ? -6 : -30)
            areas[s.key] = a
        }
        createArea(store, name: "Classes", colorHex: "#888C96", symbolName: "graduationcap", calendarId: calendarId("classes"), isClasses: true)

        // Items
        func task(_ key: String, _ title: String, due: Int? = nil) -> Item {
            createItem(store, kind: .task, title: title, areaId: areas[key]!.id, dueDate: due.map(day))
        }
        func activity(_ key: String, _ title: String) -> Item {
            createItem(store, kind: .activity, title: title, areaId: areas[key]!.id)
        }
        var activities: [String: Item] = [:]
        activities["fitness"] = activity("fitness", "Run")
        _ = activity("fitness", "Strength")
        activities["spanish"] = activity("spanish", "Conversation practice")
        _ = activity("spanish", "Anki reviews")
        activities["work"] = activity("work", "Deep work")
        activities["music"] = activity("music", "Piano practice")
        activities["home"] = activity("home", "Meal prep")
        updateItem(store, activities["spanish"]!, fullVersion: "30 min with tutor", easyVersion: "10 min voice notes")

        _ = task("work", "Finish quarterly report", due: 2)
        _ = task("work", "Reply to recruiter", due: -1)
        _ = task("home", "Book dentist appointment", due: 0)
        _ = task("work", "Book flights")
        _ = task("spanish", "Write essay draft", due: 3)
        _ = task("spanish", "Order textbook")
        _ = task("fitness", "Renew gym membership", due: -2)
        _ = task("fitness", "Plan half-marathon route")
        _ = task("music", "Learn Clair de Lune bridge", due: 6)
        _ = task("home", "Call landlord", due: 1)
        _ = task("home", "Fix bike tire")
        let doneA = task("work", "Send invoice"); updateItem(store, doneA, status: .done)
        let doneB = task("home", "Renew passport"); updateItem(store, doneB, status: .done)

        // Block logs for the past three weeks, plus planned items ahead
        let keys = specs.map(\.key)
        for offset in -21...14 {
            for (n, b) in blocks(on: day(offset)).enumerated() {
                let area = areas[b.key]!
                let ref = BlockRef(googleEventId: b.id, eventStart: b.start, areaId: area.id, plannedMinutes: b.minutes)
                let ended = b.start.addingTimeInterval(Double(b.minutes) * 60) < .now
                let roll = (abs(offset) * 7 + (keys.firstIndex(of: b.key) ?? 0) * 3 + n) % 10
                if let act = activities[b.key], offset <= 4 || roll < 5 { planItem(store, item: act, in: ref) }
                guard ended else { continue }
                switch roll {
                case 0...5: logBlock(store, ref, state: .full)
                case 6...7: logBlock(store, ref, state: .easy)
                case 8: logBlock(store, ref, state: .skipped)
                default: break
                }
            }
        }
        addUnplannedLog(store, areaId: areas["fitness"]!.id, date: day(-1).addingTimeInterval(19 * 3600), outcome: .full, minutes: 30, note: "Evening walk")
        addUnplannedLog(store, areaId: areas["spanish"]!.id, date: day(-3).addingTimeInterval(8 * 3600), outcome: .easy, minutes: 20)
        upsertTarget(store, areaId: areas["fitness"]!.id, weeklyMinutes: 240, weeklySessions: nil)

        // Inbox
        func note(_ raw: String, _ state: InboxNoteState, item: Item? = nil, hoursAgo: Double, low: Bool = false, failures: Int = 0) {
            let n = addInboxNote(store, rawText: raw)
            n.createdAt = .now.addingTimeInterval(-hoursAgo * 3600)
            n.state = state
            n.resultingItemId = item?.id
            n.sortedAt = state == .sorted ? n.createdAt.addingTimeInterval(4) : nil
            n.isLowConfidence = low
            n.failureCount = failures
            store.save()
        }
        note("anki every morning", .sorted, item: activities["spanish"], hoursAgo: 30)
        note("buy new running shoes", .sorted, item: task("fitness", "Buy running shoes"), hoursAgo: 5)
        note("piano recital thing??", .sorted, item: task("music", "Prepare piano recital piece", due: 9), hoursAgo: 3, low: true)
        note("asdf ???", .failed, hoursAgo: 2, failures: 3)
        note("call dentist thursday", .pending, hoursAgo: 0.1)
    }
}

/// A fake calendar for demo mode: area blocks from the schedule plus class events, for any date range.
struct DemoEventSource: EventSource {
    func events(calendarId: String, range: DateInterval, force: Bool) async throws -> [CalendarEvent] {
        let cal = Calendar.current
        var out: [CalendarEvent] = []
        var day = cal.startOfDay(for: range.start)
        while day < range.end {
            if calendarId == DemoMode.calendarId("classes") {
                out.append(contentsOf: DemoMode.classEvents(on: day))
            } else {
                for b in DemoMode.blocks(on: day) where DemoMode.calendarId(b.key) == calendarId {
                    let name = DemoMode.specs.first { $0.key == b.key }?.name ?? ""
                    out.append(CalendarEvent(
                        id: b.id, summary: name, start: b.start, end: b.start.addingTimeInterval(Double(b.minutes) * 60),
                        calendarId: calendarId, isAllDay: false, isCadenceBlock: true
                    ))
                }
            }
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        return out.filter { e in e.end > e.start ? (e.start < range.end && e.end > range.start) : (e.start >= range.start && e.start < range.end) }
    }
}
#endif

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
public final class InboxService {
    private let store: AppStore
    private let client: any InboxSorting
    private let keyProvider: () -> String?
    private let capReached: () -> Bool
    private let recordUsage: (String, Int, Int) -> Void
    private var settingsRevision = 0

    public private(set) var isProcessing = false
    public private(set) var processingNoteId: UUID?

    public init(
        store: AppStore,
        client: any InboxSorting = OpenRouterClient(),
        keyProvider: @escaping () -> String? = { OpenRouterKeychain.key() },
        capReached: @escaping () -> Bool = { CostTracker.isOverCap() },
        recordUsage: @escaping (String, Int, Int) -> Void = { CostTracker.record(model: $0, inputTokens: $1, outputTokens: $2) }
    ) {
        self.store = store
        self.client = client
        self.keyProvider = keyProvider
        self.capReached = capReached
        self.recordUsage = recordUsage
    }

    public var hasKey: Bool { _ = settingsRevision; return !(keyProvider()?.isEmpty ?? true) }
    public var currentKey: String { _ = settingsRevision; return keyProvider() ?? "" }
    public var monthCostUSD: Double { CostTracker.monthCostUSD }
    public var monthlyCapUSD: Double { OpenRouterSettings.monthlyCapUSD }
    public var model: String { OpenRouterSettings.model }
    public var isOverCap: Bool { _ = settingsRevision; return capReached() }

    public func setKey(_ key: String) {
        OpenRouterKeychain.setKey(key)
        settingsRevision &+= 1
    }
    public func setModel(_ model: String) {
        OpenRouterSettings.model = model
        settingsRevision &+= 1
    }
    public func setCap(_ cap: Double) {
        OpenRouterSettings.monthlyCapUSD = cap
        settingsRevision &+= 1
    }

    public func processPending() async {
        // Sending a note, opening Inbox and foregrounding can all arrive during a request.
        guard !isProcessing, hasKey, !isOverCap, !activeAreas().isEmpty else { return }
        isProcessing = true
        defer { isProcessing = false; processingNoteId = nil }
        purgeOldRawText(store)
        var attempted: Set<UUID> = []
        while !Task.isCancelled, !isOverCap, !activeAreas().isEmpty,
              let key = keyProvider(), !key.isEmpty {
            // Pick again after each await so newly captured notes are drained in this run.
            guard let note = fetchAll(InboxNote.self, in: store.context)
                .filter({ !$0.isDeleted && $0.state == .pending && !attempted.contains($0.id) })
                .min(by: { $0.createdAt < $1.createdAt }) else { break }
            attempted.insert(note.id)
            processingNoteId = note.id
            await sort(note, key: key)
        }
    }

    public func resort(_ note: InboxNote) async {
        guard !note.isDeleted, !note.rawText.isEmpty, note.id != processingNoteId else { return }
        markForResort(store, note)
        await processPending()
    }

    // MARK: - Sorting

    private func sort(_ note: InboxNote, key: String) async {
        let revision = note.updatedAt
        func isCurrent() -> Bool {
            !Task.isCancelled && !note.isDeleted && note.state == .pending && note.updatedAt == revision
        }
        guard isCurrent(), !note.rawText.isEmpty else { return }
        let request = makeRequest(for: note)
        let model = OpenRouterSettings.model
        for _ in 0..<2 {
            guard isCurrent(), !isOverCap else { return }
            do {
                let (result, inTokens, outTokens) = try await client.sort(request, apiKey: key, model: model)
                recordUsage(model, inTokens, outTokens)
                settingsRevision &+= 1
                // A manual edit, deletion or sync during the request takes precedence.
                guard isCurrent() else { return }
                if try apply(result, to: note) { return }
            } catch {
                guard isCurrent() else { return }
            }
        }
        if isCurrent() { fail(note) }
    }

    private func fail(_ note: InboxNote) {
        note.failureCount += 1
        if note.failureCount >= 3 {
            note.state = .failed
        }
        note.updatedAt = .now
        store.save()
    }

    private func apply(_ result: InboxSortResult, to note: InboxNote) throws -> Bool {
        let areas = activeAreas()
        guard let areaId = UUID(uuidString: result.areaId),
              let area = areas.first(where: { $0.id == areaId }) else {
            return false
        }
        let title = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }

        let dueDate = result.dueDate.flatMap(Self.parseDateOnly)
        let itemId: UUID

        if let previousId = note.resultingItemId, let previous = item(withId: previousId, in: store.context),
           !previous.isDeleted, previous.kind == .task {
            // Re-sorting corrects the existing item, rather than leaving duplicate tasks behind.
            // Activities can be shared by other notes and logs; never repurpose them here.
            updateItem(store, previous, title: title, kind: result.kind, areaId: area.id,
                       dueDate: .some(result.kind == .task ? dueDate : nil))
            itemId = previous.id
        } else if result.kind == .activity,
           let match = result.matchesExistingActivityId,
           let matchId = UUID(uuidString: match),
           let existing = activities(forArea: area.id, in: store.context).first(where: { $0.id == matchId }) {
            itemId = existing.id  // reuse existing activity; don't duplicate
        } else {
            let item = createItem(store, kind: result.kind, title: title, areaId: area.id, dueDate: dueDate)
            itemId = item.id
        }

        note.resultingItemId = itemId
        note.isLowConfidence = result.confidence == "low"
        note.state = .sorted
        note.sortedAt = .now
        note.updatedAt = .now
        store.save()
        return true
    }

    // MARK: - Request building

    private func activeAreas() -> [Area] {
        visibleAreas(in: store.context).filter { !$0.isClassesCalendar }
    }

    private func makeRequest(for note: InboxNote) -> InboxSortRequest {
        let areas = activeAreas()
        var activitiesByArea: [String: [ListEntry]] = [:]
        for area in areas {
            let acts = activities(forArea: area.id, in: store.context)
                .map { ListEntry(id: $0.id.uuidString, title: $0.title) }
            if !acts.isEmpty { activitiesByArea[area.id.uuidString] = acts }
        }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return InboxSortRequest(
            note: note.rawText,
            areas: areas.map { ListEntry(id: $0.id.uuidString, title: $0.name) },
            activitiesByArea: activitiesByArea,
            today: f.string(from: .now)
        )
    }

    private static func parseDateOnly(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
}

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
public final class InboxService {
    private let store: AppStore
    private let client = OpenRouterClient()

    public private(set) var isProcessing = false

    public init(store: AppStore) {
        self.store = store
    }

    public var hasKey: Bool { OpenRouterKeychain.key() != nil }
    public var currentKey: String { OpenRouterKeychain.key() ?? "" }
    public var monthCostUSD: Double { CostTracker.monthCostUSD }
    public var monthlyCapUSD: Double { OpenRouterSettings.monthlyCapUSD }
    public var model: String { OpenRouterSettings.model }
    public var isOverCap: Bool { CostTracker.isOverCap() }

    public func setKey(_ key: String) {
        OpenRouterKeychain.setKey(key)
    }
    public func setModel(_ model: String) {
        OpenRouterSettings.model = model
    }
    public func setCap(_ cap: Double) {
        OpenRouterSettings.monthlyCapUSD = cap
    }

    public func processPending() async {
        guard let key = OpenRouterKeychain.key(), !key.isEmpty else { return }
        guard !CostTracker.isOverCap() else { return }
        isProcessing = true
        defer { isProcessing = false }
        purgeOldRawText(store)
        let pending = fetchAll(InboxNote.self, in: store.context).filter { !$0.isDeleted && $0.state == .pending }
        for note in pending {
            await sort(note, key: key)
        }
    }

    public func resort(_ note: InboxNote) async {
        markForResort(store, note)
        if let key = OpenRouterKeychain.key() {
            await sort(note, key: key)
        }
    }

    // MARK: - Sorting

    private func sort(_ note: InboxNote, key: String) async {
        let request = makeRequest(for: note)
        do {
            let (result, inTokens, outTokens) = try await client.sort(request, apiKey: key, model: OpenRouterSettings.model)
            CostTracker.record(model: OpenRouterSettings.model, inputTokens: inTokens, outputTokens: outTokens)
            if try apply(result, to: note) { return }
        } catch {
            // fallthrough to retry
        }
        // retry once
        do {
            let (result, inTokens, outTokens) = try await client.sort(request, apiKey: key, model: OpenRouterSettings.model)
            CostTracker.record(model: OpenRouterSettings.model, inputTokens: inTokens, outputTokens: outTokens)
            if try apply(result, to: note) { return }
        } catch {
            // fallthrough to failure
        }
        fail(note)
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

        if result.kind == .activity,
           let match = result.matchesExistingActivityId,
           let matchId = UUID(uuidString: match),
           let existing = activities(forArea: area.id, in: store.context).first(where: { $0.id == matchId }) {
            itemId = existing.id  // reuse existing activity; don't duplicate
        } else {
            let item = createItem(store, kind: result.kind, title: title, areaId: area.id, dueDate: dueDate)
            itemId = item.id
        }

        note.resultingItemId = itemId
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
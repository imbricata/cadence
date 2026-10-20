import Foundation
import Observation

/// Holds the current `InsightSnapshot` and recomputes it (debounced) whenever stored data or events change.
/// Views read `snapshot`; nothing computes insights inside a view body.
@MainActor
@Observable
public final class InsightsModel {
    public private(set) var snapshot: InsightSnapshot = .empty

    @ObservationIgnored private let store: AppStore
    @ObservationIgnored private let events: EventStore
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(store: AppStore, events: EventStore) {
        self.store = store
        self.events = events
        recompute()
        observe()
    }

    public func recompute() {
        snapshot = computeInsights(context: store.context, events: events.events)
    }

    public func area(_ id: UUID) -> AreaStat? { snapshot.areas.first { $0.areaId == id } }
    public func activity(_ id: UUID) -> ActivityStat? { snapshot.activities.first { $0.itemId == id } }

    private func observe() {
        withObservationTracking {
            _ = store.revision
            _ = events.revision
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.task?.cancel()
                self.task = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled, let self else { return }
                    self.recompute()
                    self.observe()
                }
            }
        }
    }
}

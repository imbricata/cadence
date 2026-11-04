import XCTest
import SwiftData
import CadenceCore

private actor ControlledSorter: InboxSorting {
    private var continuation: CheckedContinuation<Void, Never>?
    private let onFirst: (@Sendable () -> Void)?
    private(set) var count = 0

    init(onFirst: (@Sendable () -> Void)? = nil) { self.onFirst = onFirst }

    func sort(_ request: InboxSortRequest, apiKey: String, model: String) async throws -> (InboxSortResult, Int, Int) {
        count += 1
        if count == 1, let onFirst {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                onFirst()
            }
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "kind": "task", "areaId": request.areas[0].id, "title": request.note,
            "confidence": "high"
        ])
        return (try JSONDecoder().decode(InboxSortResult.self, from: data), 1, 1)
    }

    func release() { continuation?.resume(); continuation = nil }
}

@MainActor
final class InboxServiceTests: XCTestCase {
    private func fixture() throws -> (AppStore, Area) {
        let store = try AppStore.inMemory()
        let area = createArea(store, name: "Home", colorHex: "#7A9C6A", symbolName: "house")
        return (store, area)
    }

    private func service(_ store: AppStore, client: ControlledSorter) -> InboxService {
        InboxService(store: store, client: client, keyProvider: { "test" }, capReached: { false }, recordUsage: { _, _, _ in })
    }

    func testConcurrentProcessingDoesNotDuplicateAndDrainsNewNotes() async throws {
        let (store, _) = try fixture()
        let started = expectation(description: "First request started")
        let client = ControlledSorter { started.fulfill() }
        let inbox = service(store, client: client)
        let first = addInboxNote(store, rawText: "Call dentist")
        let run = Task { await inbox.processPending() }
        await fulfillment(of: [started], timeout: 3)
        let second = addInboxNote(store, rawText: "Buy milk")
        await inbox.processPending()
        await client.release()
        await run.value
        let count = await client.count
        XCTAssertEqual(count, 2)
        XCTAssertEqual(fetchAll(Item.self, in: store.context).count, 2)
        XCTAssertEqual(first.state, .sorted)
        XCTAssertEqual(second.state, .sorted)
        XCTAssertFalse(inbox.isProcessing)
        XCTAssertNil(inbox.processingNoteId)
    }

    func testManualSortingWinsAgainstInFlightAI() async throws {
        let (store, area) = try fixture()
        let started = expectation(description: "Request started")
        let client = ControlledSorter { started.fulfill() }
        let inbox = service(store, client: client)
        let note = addInboxNote(store, rawText: "dentist")
        let run = Task { await inbox.processPending() }
        await fulfillment(of: [started], timeout: 3)
        let manual = createItem(store, kind: .task, title: "Book dentist for Friday", areaId: area.id)
        completeManually(store, note, itemId: manual.id)
        await client.release()
        await run.value
        XCTAssertEqual(note.resultingItemId, manual.id)
        XCTAssertEqual(manual.title, "Book dentist for Friday")
        XCTAssertEqual(fetchAll(Item.self, in: store.context).count, 1)
    }

    func testDeletedNoteCannotCreateGhostTaskAfterResponse() async throws {
        let (store, _) = try fixture()
        let started = expectation(description: "Request started")
        let client = ControlledSorter { started.fulfill() }
        let inbox = service(store, client: client)
        let note = addInboxNote(store, rawText: "Cancel this")
        let run = Task { await inbox.processPending() }
        await fulfillment(of: [started], timeout: 3)
        deleteInboxCard(store, note)
        await client.release()
        await run.value
        XCTAssertTrue(note.isDeleted)
        XCTAssertNil(note.resultingItemId)
        XCTAssertTrue(fetchAll(Item.self, in: store.context).isEmpty)
    }

    func testResortingUpdatesExistingTaskAndRemovingNotePreservesIt() async throws {
        let (store, _) = try fixture()
        let client = ControlledSorter()
        let inbox = service(store, client: client)
        let note = addInboxNote(store, rawText: "Call dentist")
        await inbox.processPending()
        let originalId = note.resultingItemId
        await inbox.resort(note)
        XCTAssertEqual(note.resultingItemId, originalId)
        let items = fetchAll(Item.self, in: store.context)
        XCTAssertEqual(items.count, 1)
        deleteInboxCard(store, note)
        XCTAssertFalse(try XCTUnwrap(items.first).isDeleted)
    }

    func testRemovingNotePreservesReusedActivity() throws {
        let (store, area) = try fixture()
        let activity = createItem(store, kind: .activity, title: "Run", areaId: area.id)
        let first = addInboxNote(store, rawText: "Run today")
        let second = addInboxNote(store, rawText: "Run tomorrow")
        completeManually(store, first, itemId: activity.id)
        completeManually(store, second, itemId: activity.id)
        deleteInboxCard(store, first)
        XCTAssertFalse(activity.isDeleted)
        XCTAssertFalse(second.isDeleted)
        XCTAssertEqual(second.resultingItemId, activity.id)
    }

    func testResortingDoesNotRepurposeASharedActivity() async throws {
        let (store, area) = try fixture()
        let shared = createItem(store, kind: .activity, title: "Run", areaId: area.id)
        let note = addInboxNote(store, rawText: "Buy running shoes")
        completeManually(store, note, itemId: shared.id)
        let inbox = service(store, client: ControlledSorter())
        await inbox.resort(note)
        XCTAssertEqual(shared.kind, .activity)
        XCTAssertEqual(shared.title, "Run")
        XCTAssertNotEqual(note.resultingItemId, shared.id)
        XCTAssertEqual(fetchAll(Item.self, in: store.context).count, 2)
    }

    func testCapIsCheckedBetweenNotes() async throws {
        let (store, _) = try fixture()
        let client = ControlledSorter()
        var capped = false
        let inbox = InboxService(store: store, client: client, keyProvider: { "test" }, capReached: { capped }, recordUsage: { _, _, _ in capped = true })
        addInboxNote(store, rawText: "First")
        addInboxNote(store, rawText: "Second")
        await inbox.processPending()
        let count = await client.count
        XCTAssertEqual(count, 1)
        XCTAssertEqual(fetchAll(InboxNote.self, in: store.context).filter { $0.state == .pending }.count, 1)
    }

    func testNoKeyOrNoAreaLeavesNotesQueuedWithoutCallingAI() async throws {
        let store = try AppStore.inMemory()
        let client = ControlledSorter()
        let note = addInboxNote(store, rawText: "Keep me")
        await service(store, client: client).processPending()
        createArea(store, name: "Home", colorHex: "#7A9C6A", symbolName: "house")
        let noKey = InboxService(store: store, client: client, keyProvider: { nil }, capReached: { false }, recordUsage: { _, _, _ in })
        await noKey.processPending()
        let count = await client.count
        XCTAssertEqual(count, 0)
        XCTAssertEqual(note.state, .pending)
    }
}

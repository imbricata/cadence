import XCTest
import CadenceCore

@MainActor
final class SyncTests: XCTestCase {
    private func area(_ id: UUID, name: String, updated: TimeInterval, deleted: Bool = false) -> AreaSnapshot {
        let a = Area(id: id, updatedAt: Date(timeIntervalSince1970: updated), isDeleted: deleted, name: name, colorHex: "#888C96", symbolName: "circle", sortOrder: 0)
        return AreaSnapshot(a)
    }

    func testNewestWins() {
        let id = UUID()
        var applied: [String] = []
        let merged = SyncEngine.merge(
            remote: [area(id, name: "remote", updated: 200)],
            local: [area(id, name: "local", updated: 100)]
        ) { applied.append($0.name) }
        XCTAssertEqual(applied, ["remote"])
        XCTAssertEqual(merged.count, 1)

        applied = []
        let merged2 = SyncEngine.merge(
            remote: [area(id, name: "remote", updated: 100)],
            local: [area(id, name: "local", updated: 200)]
        ) { applied.append($0.name) }
        XCTAssertTrue(applied.isEmpty)
        XCTAssertEqual(merged2.first?.name, "local")
    }

    func testRemoteOnlyIsApplied_LocalOnlyIsKept() {
        let r = UUID(), l = UUID()
        var applied: [UUID] = []
        let merged = SyncEngine.merge(remote: [area(r, name: "r", updated: 10)], local: [area(l, name: "l", updated: 10)]) { applied.append($0.id) }
        XCTAssertEqual(applied, [r])
        XCTAssertEqual(Set(merged.map(\.id)), [r, l])
    }

    func testTombstonePropagatesAndOldOnesPurge() {
        let id = UUID()
        var applied: [Bool] = []
        _ = SyncEngine.merge(remote: [area(id, name: "x", updated: 500, deleted: true)], local: [area(id, name: "x", updated: 100)]) { applied.append($0.isDeleted) }
        XCTAssertEqual(applied, [true])

        let old = Date().addingTimeInterval(-100 * 24 * 3600).timeIntervalSince1970
        let merged = SyncEngine.merge(remote: [area(id, name: "x", updated: old, deleted: true)], local: []) { _ in }
        XCTAssertTrue(merged.isEmpty)
    }

    func testOldInboxJSONWithoutNewFieldsDecodes() throws {
        let json = """
        [{"id":"\(UUID().uuidString)","updatedAt":"2026-01-01T00:00:00Z","isDeleted":false,"rawText":"hi",
          "createdAt":"2026-01-01T00:00:00Z","state":"sorted"}]
        """
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let notes = try dec.decode([InboxNoteSnapshot].self, from: Data(json.utf8))
        XCTAssertEqual(notes.first?.isLowConfidence, false)
        XCTAssertEqual(notes.first?.failureCount, 0)
    }
}

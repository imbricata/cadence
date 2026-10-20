import SwiftUI
import SwiftData
import CadenceCore

/// What the calendar shows about a block beyond its event: log state and planned item titles.
struct BlockInfo {
    var state: BlockLogState
    var itemTitles: [String]
}

struct BlockInfoIndex {
    var map: [String: BlockInfo] = [:]

    static func key(_ id: String, _ start: Date) -> String { "\(id)|\(Int(start.timeIntervalSince1970))" }
    func info(for e: CalendarEvent) -> BlockInfo? { map[Self.key(e.id, e.start)] }

    init() {}

    init(logs: [BlockLog], entries: [BlockEntry], items: [Item]) {
        let titles = Dictionary(items.filter { !$0.isDeleted }.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        var byLog: [UUID: [String]] = [:]
        for e in entries where !e.isDeleted {
            if let id = e.itemId, let t = titles[id] { byLog[e.blockLogId, default: []].append(t) }
        }
        for log in logs where !log.isDeleted {
            map[Self.key(log.googleEventId, log.eventStart)] = BlockInfo(state: log.state, itemTitles: (byLog[log.id] ?? []).sorted())
        }
    }
}

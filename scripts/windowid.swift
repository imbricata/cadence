import CoreGraphics
import Foundation

// usage: windowid <owner name>   -> prints the id of the largest on-screen window owned by that app
let owner = CommandLine.arguments.dropFirst().first ?? "Cadence"
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let best = list
    .filter { ($0["kCGWindowOwnerName"] as? String) == owner && ($0["kCGWindowLayer"] as? Int) == 0 }
    .max { a, b in
        func area(_ w: [String: Any]) -> Double {
            let r = w["kCGWindowBounds"] as? [String: Double] ?? [:]
            return (r["Width"] ?? 0) * (r["Height"] ?? 0)
        }
        return area(a) < area(b)
    }
if let id = best?["kCGWindowNumber"] as? Int { print(id) }

import CoreGraphics
import Foundation

// usage: windowid <owner name> [--bounds]
// Prints the id of the largest on-screen window owned by that app (or "x,y,w,h" with --bounds).
let args = Array(CommandLine.arguments.dropFirst())
let owner = args.first ?? "Cadence"
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
func area(_ w: [String: Any]) -> Double {
    let r = w["kCGWindowBounds"] as? [String: Double] ?? [:]
    return (r["Width"] ?? 0) * (r["Height"] ?? 0)
}
let best = list
    .filter { ($0["kCGWindowOwnerName"] as? String) == owner && ($0["kCGWindowLayer"] as? Int) == 0 }
    .max { area($0) < area($1) }
if args.contains("--all") {
    // every window Cadence owns (main window + popovers), so screenshots never include other apps
    for w in list where (w["kCGWindowOwnerName"] as? String) == owner {
        if let id = w["kCGWindowNumber"] as? Int { print(id) }
    }
} else if args.contains("--bounds"), let r = best?["kCGWindowBounds"] as? [String: Double] {
    print("\(Int(r["X"] ?? 0)),\(Int(r["Y"] ?? 0)),\(Int(r["Width"] ?? 0)),\(Int(r["Height"] ?? 0))")
} else if let id = best?["kCGWindowNumber"] as? Int {
    print(id)
}

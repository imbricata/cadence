import CadenceCore

/// Tasks by due date (soonest first, undated last), then oldest first.
func taskOrder(_ a: Item, _ b: Item) -> Bool {
    switch (a.dueDate, b.dueDate) {
    case let (x?, y?): return x != y ? x < y : a.createdAt < b.createdAt
    case (nil, nil): return a.createdAt < b.createdAt
    case (nil, _): return false
    case (_, nil): return true
    }
}

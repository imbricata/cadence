import CadenceCore

/// Tasks by due date (soonest first, undated last), then oldest first.
func taskOrder(_ a: Item, _ b: Item) -> Bool {
    TaskAgenda.ordered(a, b)
}

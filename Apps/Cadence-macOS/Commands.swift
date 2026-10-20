import SwiftUI

enum PlanMode: String, CaseIterable, Identifiable {
    case day = "Day", week = "Week"
    var id: String { rawValue }
}

/// What the window-level commands can do. Published by `RootView` with `focusedSceneValue`.
struct RootActions {
    var newNote: () -> Void
}

/// What the Plan commands can do. Published by `PlanView`, so the Plan menu is only enabled while Plan is showing.
struct PlanActions {
    var newBlock: () -> Void
    var previous: () -> Void
    var next: () -> Void
    var today: () -> Void
    var refresh: () -> Void
    var toggleBacklog: () -> Void
    var setMode: (PlanMode) -> Void
}

extension FocusedValues {
    @Entry var rootActions: RootActions?
    @Entry var planActions: PlanActions?
}

struct CadenceCommands: Commands {
    @FocusedValue(\.rootActions) private var root
    @FocusedValue(\.planActions) private var plan

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") { root?.newNote() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(root == nil)
            Button("New Block") { plan?.newBlock() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(plan == nil)
        }
        CommandMenu("Plan") {
            Button("Previous") { plan?.previous() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Button("Next") { plan?.next() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Today") { plan?.today() }
                .keyboardShortcut("t", modifiers: .command)
            Divider()
            Button("Day") { plan?.setMode(.day) }
                .keyboardShortcut("1", modifiers: .command)
            Button("Week") { plan?.setMode(.week) }
                .keyboardShortcut("2", modifiers: .command)
            Divider()
            Button("Refresh") { plan?.refresh() }
                .keyboardShortcut("r", modifiers: .command)
            Button("Toggle Backlog") { plan?.toggleBacklog() }
                .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}

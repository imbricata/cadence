import SwiftUI

struct CadenceCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") {
                NotificationCenter.default.post(name: .commandNewNote, object: nil)
                NotificationCenter.default.post(name: .commandFocusInbox, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Block") {
                NotificationCenter.default.post(name: .commandNewBlock, object: nil)
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
        }
        CommandMenu("Plan") {
            Button("Previous Day") { NotificationCenter.default.post(name: .commandPrevDay, object: nil) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Button("Next Day") { NotificationCenter.default.post(name: .commandNextDay, object: nil) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Today") { NotificationCenter.default.post(name: .commandToday, object: nil) }
                .keyboardShortcut("t", modifiers: .command)
            Divider()
            Button("Sync") { NotificationCenter.default.post(name: .commandSync, object: nil) }
                .keyboardShortcut("s", modifiers: .command)
        }
    }
}
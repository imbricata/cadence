import Foundation

public extension Notification.Name {
    static let openCapture = Notification.Name("cadence.openCapture")
    static let commandNewNote = Notification.Name("cadence.command.newNote")
    static let commandNewBlock = Notification.Name("cadence.command.newBlock")
    static let commandPrevDay = Notification.Name("cadence.command.prevDay")
    static let commandNextDay = Notification.Name("cadence.command.nextDay")
    static let commandToday = Notification.Name("cadence.command.today")
    static let commandSync = Notification.Name("cadence.command.sync")
    static let commandFocusInbox = Notification.Name("cadence.command.focusInbox")
}
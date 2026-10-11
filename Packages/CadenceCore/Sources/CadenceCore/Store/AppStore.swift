import Foundation
import SwiftData
import Observation

public enum CadenceSchema {
    public static let models: [any PersistentModel.Type] = [
        Area.self, Item.self, InboxNote.self, BlockLog.self, BlockEntry.self, UnplannedLog.self, Target.self
    ]

    public static var schema: Schema { Schema(models) }

    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [config])
    }
}

@MainActor
@Observable
public final class AppStore {
    public let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    public var context: ModelContext { container.mainContext }

    public static func live() throws -> AppStore {
        AppStore(container: try CadenceSchema.makeContainer())
    }

    public static func inMemory() throws -> AppStore {
        AppStore(container: try CadenceSchema.makeContainer(inMemory: true))
    }

    public func save() {
        do { try context.save() } catch { print("save error: \(error)") }
    }
}
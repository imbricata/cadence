import Foundation
import SwiftData

// MARK: - Areas

@MainActor
@discardableResult
public func createArea(_ store: AppStore, name: String, colorHex: String, symbolName: String, calendarId: String = "", isClasses: Bool = false) -> Area {
    let sortOrder = (allAreas(in: store.context).map(\.sortOrder).max() ?? -1) + 1
    let area = Area(name: name, colorHex: colorHex, symbolName: symbolName, sortOrder: sortOrder, googleCalendarId: calendarId, isClassesCalendar: isClasses)
    store.context.insert(area)
    store.save()
    return area
}

@MainActor
public func updateArea(_ store: AppStore, _ area: Area, name: String? = nil, colorHex: String? = nil, symbolName: String? = nil, calendarId: String? = nil, isArchived: Bool? = nil) {
    if let name { area.name = name }
    if let colorHex { area.colorHex = colorHex }
    if let symbolName { area.symbolName = symbolName }
    if let calendarId { area.googleCalendarId = calendarId }
    if let isArchived { area.isArchived = isArchived }
    touch(area)
    store.save()
}

/// Soft delete (tombstone) for sync.
@MainActor
public func deleteArea(_ store: AppStore, _ area: Area) {
    area.isDeleted = true
    touch(area)
    store.save()
}

@MainActor
public func reorderAreas(_ store: AppStore, _ areas: [Area]) {
    for (i, area) in areas.enumerated() {
        area.sortOrder = i
        touch(area)
    }
    store.save()
}

// MARK: - Items

@MainActor
@discardableResult
public func createItem(_ store: AppStore, kind: ItemKind, title: String, areaId: UUID, dueDate: Date? = nil) -> Item {
    let item = Item(kind: kind, title: title, areaId: areaId, dueDate: dueDate)
    store.context.insert(item)
    store.save()
    return item
}

@MainActor
public func updateItem(
    _ store: AppStore, _ item: Item,
    title: String? = nil, kind: ItemKind? = nil, areaId: UUID? = nil,
    dueDate: Date?? = nil, fullVersion: String?? = nil, easyVersion: String?? = nil,
    notes: String?? = nil, status: ItemStatus? = nil
) {
    if let title { item.title = title }
    if let kind { item.kind = kind }
    if let areaId { item.areaId = areaId }
    if let dueDate { item.dueDate = dueDate }
    if let fullVersion { item.fullVersion = fullVersion }
    if let easyVersion { item.easyVersion = easyVersion }
    if let notes { item.notes = notes }
    if let status { item.status = status }
    if status == .done { item.completedAt = .now }
    if status == .open { item.completedAt = nil }
    touch(item)
    store.save()
}

@MainActor
public func deleteItem(_ store: AppStore, _ item: Item) {
    item.isDeleted = true
    touch(item)
    store.save()
}

// MARK: - Shared

func touch(_ model: any SyncedModel) {
    model.updatedAt = .now
}
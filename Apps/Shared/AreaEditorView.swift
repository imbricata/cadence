import SwiftUI
import CadenceCore

struct AreaEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(GoogleService.self) private var google
    @Environment(\.dismiss) private var dismiss
    let area: Area?

    @State private var name: String
    @State private var colorHex: String
    @State private var symbolName: String

    init(area: Area?) {
        self.area = area
        _name = State(initialValue: area?.name ?? "")
        _colorHex = State(initialValue: area?.colorHex ?? AreaPalette.all.first!)
        _symbolName = State(initialValue: area?.symbolName ?? "circle")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                }
                Section("Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(AreaPalette.all, id: \.self) { hex in
                            ZStack {
                                Circle().fill(Color(hex: hex)).frame(width: 30, height: 30)
                                if colorHex == hex {
                                    Circle().stroke(Color.primary, lineWidth: 2).frame(width: 36, height: 36)
                                }
                            }
                            .onTapGesture { colorHex = hex }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Symbol") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(symbolChoices, id: \.self) { sym in
                            Image(systemName: sym)
                                .font(.body)
                                .foregroundStyle(symbolName == sym ? Color(hex: colorHex) : Color.secondary)
                                .frame(width: 30, height: 30)
                                .onTapGesture { symbolName = sym }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(area == nil ? "New Area" : "Edit Area")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let area {
            updateArea(store, area, name: trimmed, colorHex: colorHex, symbolName: symbolName)
            Task { await google.applyAreaAppearance(area) }
        } else {
            let new = createArea(store, name: trimmed, colorHex: colorHex, symbolName: symbolName)
            Task { await google.ensureCalendar(for: new) }
        }
        dismiss()
    }
}
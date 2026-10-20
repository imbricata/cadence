import SwiftUI
import UniformTypeIdentifiers
import CadenceCore

struct JSONExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(decoding: data, as: UTF8.self)
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct ExportSection: View {
    @Environment(AppStore.self) private var store
    @State private var exporting = false
    @State private var document = JSONExportDocument(text: "")

    var body: some View {
        Section("Data") {
            Button("Export JSON…") {
                document = JSONExportDocument(text: String(decoding: exportJSON(context: store.context), as: UTF8.self))
                exporting = true
            }
        }
        .fileExporter(
            isPresented: $exporting,
            document: document,
            contentType: .json,
            defaultFilename: "cadence-export"
        ) { _ in }
    }
}
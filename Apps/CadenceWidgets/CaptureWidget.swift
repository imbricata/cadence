import WidgetKit
import SwiftUI

struct CaptureEntry: TimelineEntry {
    let date: Date
}

struct CaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaptureEntry { CaptureEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (CaptureEntry) -> Void) { completion(CaptureEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CaptureEntry>) -> Void) {
        completion(Timeline(entries: [CaptureEntry(date: .now)], policy: .never))
    }
}

struct CaptureWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                    Spacer()
                    Text("Capture")
                        .font(.headline)
                    Text("A quick note")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            case .accessoryCircular:
                Image(systemName: "plus.circle.fill")
            default:
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Capture")
                }
            }
        }
        .widgetURL(URL(string: "cadence://capture"))
    }
}

struct CaptureWidget: Widget {
    let kind = "CaptureWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CaptureProvider()) { _ in
            CaptureWidgetView()
        }
        .configurationDisplayName("Capture")
        .description("Quickly open the inbox to capture a note.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct CadenceWidgets: WidgetBundle {
    var body: some Widget {
        CaptureWidget()
    }
}
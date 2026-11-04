import SwiftUI
import SwiftData
import AppKit
import CadenceCore

@main
struct CadenceApp: App {
    @State private var services = AppServices.make()

    var body: some Scene {
        WindowGroup {
            RootView()
                .cadenceEnvironment(services)
                .frame(minWidth: 980, minHeight: 600)
                .background(FillScreenOnLaunch())
        }
        .defaultSize(width: 1320, height: 840)

        Settings {
            SettingsView()
                .cadenceEnvironment(services)
        }
        .commands {
            CadenceCommands()
        }
    }
}

/// Zooms the first window to fill the screen when the app launches, exactly like double-clicking
/// the title bar: the menu bar and Dock stay visible. Runs once per launch, so reopening a window
/// is left alone. Skipped in demo mode so screenshots keep their frame.
private struct FillScreenOnLaunch: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Probe: NSView {
        nonisolated(unsafe) private static var didRun = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !Self.didRun else { return }
            #if DEBUG
            if DemoMode.isEnabled { return }
            #endif
            Self.didRun = true
            // Let the window finish its first layout, then zoom it (only if it isn't already zoomed
            // or in full screen, since zoom() toggles).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if !window.isZoomed && !window.styleMask.contains(.fullScreen) { window.zoom(nil) }
            }
        }
    }
}

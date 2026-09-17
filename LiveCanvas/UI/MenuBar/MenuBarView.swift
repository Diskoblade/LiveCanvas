import SwiftUI

/// Contents of the menu bar extra. Kept to the actions that make sense without the window.
struct MenuBarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open \(AppInfo.name)") {
            openWindow(id: "main")
            state.activateMainWindow()
        }

        Divider()

        if let asset = state.desktopAsset {
            Text("Current: \(asset.displayName)")
        } else {
            Text("No wallpaper set")
        }

        Button(state.isPaused ? "Resume Animation" : "Pause Animation") {
            state.togglePaused()
        }
        .disabled(state.desktopAsset == nil)

        Button("Next Wallpaper") { state.nextWallpaper() }
            .disabled(state.library.assets.count < 2)

        Divider()

        Button("Lock Screen…") {
            state.selectedSection = .lockScreen
            openWindow(id: "main")
            state.activateMainWindow()
        }

        Button("Settings…") {
            state.selectedSection = .settings
            openWindow(id: "main")
            state.activateMainWindow()
        }

        Divider()

        Button("Quit \(AppInfo.name)") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

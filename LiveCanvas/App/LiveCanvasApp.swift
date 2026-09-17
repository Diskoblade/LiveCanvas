import SwiftUI

@main
struct LiveCanvasApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState.shared

    var body: some Scene {
        Window(AppInfo.name, id: "main") {
            // Under the test runner the host app must stay inert: building the real UI
            // would start the wallpaper engine, read the user's Aerial store and contend
            // with the tests for hardware video decoders.
            if AppInfo.isRunningTests {
                Color.clear.frame(width: 1, height: 1)
            } else {
                MainWindowView()
                    .environment(state)
                    .frame(minWidth: 860, minHeight: 540)
            }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1080, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Wallpaper…") { state.presentImportPanel() }
                    .keyboardShortcut("o", modifiers: .command)
            }
        }

        MenuBarExtra(AppInfo.name, systemImage: "play.rectangle.on.rectangle", isInserted: Binding(
            get: { !AppInfo.isRunningTests && state.settings.showInMenuBar },
            set: { v in state.preferences.update { $0.showInMenuBar = v } })) {
            MenuBarView().environment(state)
        }
    }
}

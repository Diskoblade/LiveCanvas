import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !AppInfo.isRunningTests else { return }
        Log.app.info("applicationDidFinishLaunching")
    }

    /// Files opened via Finder / Dock / `open -a` are imported into the library.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard !AppInfo.isRunningTests else { return }
        let supported = urls.filter(VideoAssetManager.isSupported)
        Log.app.info("Open request for \(urls.count) file(s), \(supported.count) supported")
        guard !supported.isEmpty else { return }
        Task { @MainActor in
            await AppState.shared.library.importFiles(supported)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Wallpaper playback continues with the main window closed (Milestone 2+).
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }
}

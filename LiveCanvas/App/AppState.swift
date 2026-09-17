import Foundation
import Observation
import AppKit

/// Root observable object. Owns the services and the cross-cutting UI state.
@MainActor
@Observable
final class AppState {
    /// Process-wide instance; the SwiftUI scene and AppDelegate share it.
    static let shared = AppState()

    let library: VideoAssetManager
    let preferences: PreferencesStore
    let preview = PreviewPlayer()
    let displayManager = DisplayManager()
    let playlists: PlaylistCoordinator
    let engine: WallpaperEngine
    let system: SystemCoordinator
    let lockScreen: LockScreenController

    var selectedSection: SidebarSection = .library {
        didSet {
            guard selectedSection != oldValue else { return }
            preferences.update { $0.lastSection = selectedSection.rawValue }
        }
    }
    var presentedAsset: WallpaperAsset?
    var presentedError: PresentableError?

    init(library: VideoAssetManager? = nil, preferences: PreferencesStore? = nil) {
        self.library = library ?? VideoAssetManager()
        self.preferences = preferences ?? PreferencesStore()
        let library = self.library
        let playlists = PlaylistCoordinator(preferences: self.preferences, library: self.library)
        self.playlists = playlists
        let engine = WallpaperEngine(library: self.library, preferences: self.preferences,
                                     displays: displayManager, playlists: playlists)
        self.engine = engine
        system = SystemCoordinator(engine: engine, preferences: self.preferences)
        lockScreen = LockScreenController(library: self.library, preferences: self.preferences)
        library.onAssetDeleted = { [weak self] asset in
            self?.handleDeleted(asset)
        }
        Log.app.info("\(AppInfo.name, privacy: .public) \(AppInfo.version, privacy: .public) (\(AppInfo.build, privacy: .public)) starting on macOS \(OSVersion.current.description, privacy: .public)")
        selectedSection = SidebarSection(rawValue: self.preferences.settings.lastSection) ?? .library
        // Under the test runner the app is only a host: starting the engine here would put
        // real wallpaper windows on the desktop and contend for video decoders.
        if !AppInfo.isRunningTests {
            engine.start()
        }
    }

    var settings: AppSettings { preferences.settings }

    // MARK: Assignment intents (engine wiring arrives in Milestone 2)

    func setDesktop(_ asset: WallpaperAsset) {
        preferences.update { s in
            s.desktop.useSameOnAllDisplays = true
            s.desktop.global = .asset(asset.id, fitMode: s.desktop.global?.fitMode)
        }
    }

    /// Assigns a playlist to every display.
    func setDesktopPlaylist(_ playlist: Playlist) {
        preferences.update { s in
            s.desktop.useSameOnAllDisplays = true
            s.desktop.global = .playlist(playlist.id, fitMode: s.desktop.global?.fitMode)
        }
        playlists.playlistDidChange(playlist.id)
        playlists.start()
    }

    func setLockScreen(_ asset: WallpaperAsset) {
        preferences.update { s in
            s.lockScreen.useDesktopWallpaper = false
            s.lockScreen.assetID = asset.id
        }
    }

    func setBoth(_ asset: WallpaperAsset) {
        setDesktop(asset)
        preferences.update { s in
            s.lockScreen.useDesktopWallpaper = true
            s.lockScreen.assetID = asset.id
        }
    }

    /// Assigns an asset to one display. Switches out of "same on all displays" mode so the
    /// user's per-display intent is not silently overwritten by the global assignment.
    func assign(_ asset: WallpaperAsset, to display: DisplayConfiguration) {
        preferences.update { s in
            if s.desktop.useSameOnAllDisplays {
                s.desktop.useSameOnAllDisplays = false
                // Seed every other display with what it was already showing.
                if let global = s.desktop.global {
                    for d in displayManager.displays where d.id != display.id {
                        s.desktop.perDisplay[d.id] = s.desktop.perDisplay[d.id] ?? global
                    }
                }
            }
            let existingFit = s.desktop.perDisplay[display.id]?.fitMode
            s.desktop.perDisplay[display.id] = .asset(asset.id, fitMode: existingFit)
        }
    }

    func clearAssignment(for display: DisplayConfiguration) {
        preferences.update { s in
            if s.desktop.useSameOnAllDisplays {
                s.desktop.useSameOnAllDisplays = false
                if let global = s.desktop.global {
                    for d in displayManager.displays where d.id != display.id {
                        s.desktop.perDisplay[d.id] = s.desktop.perDisplay[d.id] ?? global
                    }
                }
                s.desktop.global = nil
            }
            s.desktop.perDisplay[display.id] = nil
        }
    }

    func setFitMode(_ mode: FitMode, for display: DisplayConfiguration) {
        preferences.update { s in
            if s.desktop.useSameOnAllDisplays {
                s.desktop.global?.fitMode = mode
            } else if var a = s.desktop.perDisplay[display.id] {
                a.fitMode = mode
                s.desktop.perDisplay[display.id] = a
            } else if var g = s.desktop.global {
                g.fitMode = mode
                s.desktop.perDisplay[display.id] = g
            }
        }
    }

    var desktopAsset: WallpaperAsset? {
        library.asset(id: settings.desktop.global?.assetID)
    }

    var lockScreenAsset: WallpaperAsset? {
        settings.lockScreen.useDesktopWallpaper ? desktopAsset : library.asset(id: settings.lockScreen.assetID)
    }

    func delete(_ asset: WallpaperAsset) {
        preview.stop(if: asset.id)
        if presentedAsset?.id == asset.id { presentedAsset = nil }
        library.delete(asset)
    }

    private func handleDeleted(_ asset: WallpaperAsset) {
        preferences.update { s in
            s.desktop.remove(assetID: asset.id)
            if s.lockScreen.assetID == asset.id { s.lockScreen.assetID = nil }
            for i in s.playlists.indices { s.playlists[i].assetIDs.removeAll { $0 == asset.id } }
        }
    }

    // MARK: Menu bar intents

    var isPaused: Bool { system.isPaused }

    func togglePaused() { system.togglePaused() }

    /// Advances the assigned playlist, or cycles through the library when a single
    /// wallpaper is assigned.
    func nextWallpaper() {
        if playlists.advanceNow() { return }
        let assets = library.assets.sorted { $0.dateImported < $1.dateImported }
        guard !assets.isEmpty else { return }
        let currentID = settings.desktop.global?.assetID ?? settings.desktop.perDisplay.values.first?.assetID
        let index = assets.firstIndex { $0.id == currentID }
        let next = assets[((index ?? -1) + 1) % assets.count]
        setDesktop(next)
    }

    /// What the desktop is showing right now, following a playlist when one is assigned.
    var currentlyPlayingAsset: WallpaperAsset? {
        playlists.resolveAsset(for: settings.desktop.assignment(for: displayManager.displays.first?.id ?? ""))
            ?? desktopAsset
    }

    func setStartAtLogin(_ enabled: Bool) {
        let ok = system.loginItem.setEnabled(enabled)
        preferences.update { $0.startAtLogin = system.loginItem.isEnabled }
        if !ok {
            presentedError = PresentableError(
                title: "Could not change the login item",
                message: system.loginItem.lastError ?? "macOS declined the request. You can enable \(AppInfo.name) manually in System Settings › General › Login Items.")
        }
    }

    /// Brings the main window forward (menu bar → Open).
    func activateMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            return
        }
        // The Window scene was closed; ask SwiftUI to re-open it.
        NSApp.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
    }

    // MARK: Import UI

    func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "Add Wallpaper"
        panel.prompt = "Add"
        panel.allowedContentTypes = VideoAssetManager.supportedTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            let urls = panel.urls
            Task { await self.library.importFiles(urls) }
        }
    }
}

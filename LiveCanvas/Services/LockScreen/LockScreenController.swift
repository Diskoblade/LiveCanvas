import Foundation
import Observation

/// Main-actor front end for the Lock Screen feature. Owns the installer, the current
/// status, and the busy/error state the UI observes.
@MainActor
@Observable
final class LockScreenController {
    private(set) var status: LockScreenStatus = .checking
    private(set) var installerStatus: LockScreenInstallerStatus?
    private(set) var report: AerialStoreReport?
    /// Apple videos that another tool appears to have overwritten in place.
    private(set) var mediaFindings: [AerialMediaAudit.Finding] = []
    private(set) var installation: LockScreenInstallation?
    private(set) var isBusy = false
    private(set) var busyDescription = ""
    var lastError: PresentableError?

    private let installer: any LockScreenWallpaperInstalling
    private let tahoe: TahoeAerialInstaller?
    private let library: VideoAssetManager
    private let preferences: PreferencesStore

    init(library: VideoAssetManager,
         preferences: PreferencesStore,
         installer: (any LockScreenWallpaperInstalling)? = nil) {
        self.library = library
        self.preferences = preferences
        let concrete = installer as? TahoeAerialInstaller ?? (installer == nil ? TahoeAerialInstaller() : nil)
        self.tahoe = concrete
        self.installer = installer ?? concrete!
        self.installation = concrete?.loadRecord()
    }

    var isSupported: Bool { installerStatus?.isReady ?? false }

    /// Non-blocking context, for example another app having edited the store.
    var warning: String? {
        var parts: [String] = []
        if case .ready(let warning) = installerStatus, let warning { parts.append(warning) }
        if !mediaFindings.isEmpty {
            let names = mediaFindings.map(\.name).joined(separator: ", ")
            let verb = mediaFindings.count == 1 ? "no longer matches" : "no longer match"
            parts.append("\(Pluralize.count(mediaFindings.count, "Apple wallpaper video")) on this Mac (\(names)) \(verb) what macOS lists for it, so another app replaced the file itself. \(AppInfo.name) leaves those alone and cannot restore them.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }


    /// The asset the Lock Screen is set to use, according to the app's preferences.
    var selectedAsset: WallpaperAsset? {
        let settings = preferences.settings
        if settings.lockScreen.useDesktopWallpaper {
            return library.asset(id: settings.desktop.global?.assetID)
        }
        return library.asset(id: settings.lockScreen.assetID)
    }

    // MARK: Refresh

    func refresh() async {
        let installer = self.installer
        let tahoe = self.tahoe
        let status = await installer.status()
        installerStatus = status
        report = tahoe.map { AerialStoreValidator(locator: $0.locator).inspect() }
        installation = tahoe?.loadRecord()

        // Deep media audit: catches Apple videos replaced on disk, which a manifest-only
        // comparison cannot see. Probing is off the main actor and best-effort.
        if let tahoe, report?.isUsable == true {
            let validator = AerialStoreValidator(locator: tahoe.locator)
            if let manifest = try? validator.loadManifest(), let pristine = try? validator.pristineAssetIDs() {
                mediaFindings = await AerialMediaAudit(locator: tahoe.locator)
                    .auditAppleAssets(manifest: manifest, pristineIDs: pristine)
            }
        }

        switch status {
        case .unsupportedOS(let reason):
            self.status = .unsupported(reason: reason)
        case .storeUnavailable(let reason):
            self.status = .needsAttention(reason: reason)
        case .ready:
            if let installation, tahoe?.isInstallationLive(installation) == true {
                self.status = .installed(assetID: installation.libraryAssetID, installedAt: installation.installedAt)
            } else if installation != nil {
                self.status = .needsAttention(reason: "The Lock Screen wallpaper was changed outside \(AppInfo.name). Restore to clear this, or apply again.")
            } else {
                self.status = .ready
            }
        }
    }

    // MARK: Apply / Restore

    func apply() async {
        guard let asset = selectedAsset else {
            lastError = PresentableError(LiveCanvasError.lockScreenUnavailable("Choose a wallpaper for the Lock Screen first."))
            return
        }
        isBusy = true
        busyDescription = "Preparing “\(asset.displayName)”…"
        defer { isBusy = false; busyDescription = "" }

        do {
            let videoURL = library.mediaURL(for: asset)
            let probe = try await VideoMetadataService().probe(videoURL)
            busyDescription = "Installing…"
            let request = LockScreenInstallRequest(
                assetID: asset.id,
                displayName: asset.displayName,
                videoURL: videoURL,
                probe: probe,
                posterURL: library.thumbnailURL(for: asset))
            installation = try await installer.install(request: request)
            preferences.update { $0.lockScreen.enabled = true }
            Log.lockscreen.info("Lock Screen wallpaper applied")
        } catch {
            Log.lockscreen.error("Apply failed: \(error.localizedDescription, privacy: .public)")
            lastError = PresentableError(error)
            preferences.update { $0.lockScreen.enabled = false }
        }
        await refresh()
    }

    func restore() async {
        isBusy = true
        busyDescription = "Restoring Apple's Lock Screen wallpaper…"
        defer { isBusy = false; busyDescription = "" }
        do {
            try await installer.restoreLatest()
            preferences.update { $0.lockScreen.enabled = false }
        } catch {
            Log.lockscreen.error("Restore failed: \(error.localizedDescription, privacy: .public)")
            lastError = PresentableError(error)
        }
        await refresh()
    }

    /// Backups on disk, newest first (shown in the UI so a restore is always possible).
    func availableBackups() -> [BackupManifest] {
        BackupManager().listBackups()
    }
}

import AppKit
import Observation

/// Tracks connected displays and publishes `DisplayConfiguration` snapshots.
/// Uses NSApplication.didChangeScreenParametersNotification (no polling); macOS emits
/// several notifications per topology change, so updates are coalesced briefly.
@MainActor
@Observable
final class DisplayManager {
    private(set) var displays: [DisplayConfiguration] = []
    private var observer: NSObjectProtocol?
    private var coalesceTask: Task<Void, Never>?

    init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleRefresh() }
        }
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func scheduleRefresh() {
        coalesceTask?.cancel()
        coalesceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    func refresh() {
        let new = NSScreen.screens.map(Self.configuration(for:))
        guard new != displays else { return }
        let added = Set(new.map(\.id)).subtracting(displays.map(\.id))
        let removed = Set(displays.map(\.id)).subtracting(new.map(\.id))
        Log.displays.info("Displays changed: \(new.count) active, +\(added.count) -\(removed.count)")
        for d in new {
            Log.displays.debug("\(d.name, privacy: .public) [\(d.id, privacy: .public)] \(d.pointResolutionLabel, privacy: .public) @\(d.scaleLabel, privacy: .public) frame=\(NSStringFromRect(d.frame), privacy: .public)")
        }
        displays = new
    }

    func screen(for display: DisplayConfiguration) -> NSScreen? {
        NSScreen.screens.first { Self.identifier(for: $0) == display.id }
    }

    // MARK: Identity

    static func configuration(for screen: NSScreen) -> DisplayConfiguration {
        let directID = directDisplayID(for: screen)
        return DisplayConfiguration(
            id: identifier(for: screen),
            directDisplayID: directID,
            name: screen.localizedName,
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            backingScaleFactor: screen.backingScaleFactor,
            isBuiltIn: CGDisplayIsBuiltin(directID) != 0,
            isMain: screen == NSScreen.main
        )
    }

    static func directDisplayID(for screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Stable identifier: CoreGraphics display UUID when available (survives reconnects on
    /// the same port/EDID), else vendor/model/serial.
    static func identifier(for screen: NSScreen) -> String {
        let id = directDisplayID(for: screen)
        if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return "vendor-\(CGDisplayVendorNumber(id))-model-\(CGDisplayModelNumber(id))-serial-\(CGDisplaySerialNumber(id))"
    }
}

import Foundation
import IOKit.ps
import Observation

/// Power source and Low Power Mode state. Uses IOKit run-loop notifications and the
/// system's NSProcessInfoPowerStateDidChange notification; no polling.
@MainActor
@Observable
final class PowerMonitor {
    private(set) var isOnBattery = false
    private(set) var isLowPowerMode = false
    private(set) var batteryPercentage: Int?

    private var runLoopSource: CFRunLoopSource?
    private var powerStateObserver: NSObjectProtocol?

    init() {
        refresh()
        // IOKit calls back on the main run loop whenever the power source changes.
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refresh() }
        }, context)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }

        powerStateObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    isolated deinit {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode) }
        if let powerStateObserver { NotificationCenter.default.removeObserver(powerStateObserver) }
    }

    func refresh() {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        var onBattery = false
        var percent: Int?

        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else { continue }
                if let state = desc[kIOPSPowerSourceStateKey] as? String {
                    onBattery = (state == kIOPSBatteryPowerValue)
                }
                if let current = desc[kIOPSCurrentCapacityKey] as? Int, let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 {
                    percent = Int((Double(current) / Double(max) * 100).rounded())
                }
            }
        }

        guard onBattery != isOnBattery || lowPower != isLowPowerMode || percent != batteryPercentage else { return }
        isOnBattery = onBattery
        isLowPowerMode = lowPower
        batteryPercentage = percent
        Log.power.info("Power: \(onBattery ? "battery" : "AC", privacy: .public) lowPower=\(lowPower) level=\(percent ?? -1)")
    }

    /// True when the Mac has an internal battery at all (affects which settings are shown).
    var hasBattery: Bool { batteryPercentage != nil }
}

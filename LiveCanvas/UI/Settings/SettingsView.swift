import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state

    private var playback: PlaybackSettings { state.settings.playback }

    var body: some View {
        Form {
            Section("Playback") {
                Picker("Default fit mode", selection: binding(\.defaultFitMode)) {
                    ForEach(FitMode.allCases) { Text($0.displayName).tag($0) }
                }
                .help(playback.defaultFitMode.help)

                Picker("Quality", selection: binding(\.quality)) {
                    ForEach(PlaybackQuality.allCases) { Text($0.displayName).tag($0) }
                }

                Toggle("Allow wallpaper audio", isOn: binding(\.allowAudio))
                Text("Wallpapers are silent by default. The Lock Screen copy never has audio.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Energy") {
                Toggle("Pause while another app is full screen", isOn: binding(\.pauseWhenAppFullScreen))
                Toggle("Pause in Low Power Mode", isOn: binding(\.pauseInLowPowerMode))
                if state.system.power.hasBattery {
                    Picker("On battery", selection: binding(\.batteryBehavior)) {
                        ForEach(BatteryBehavior.allCases) { Text($0.displayName).tag($0) }
                    }
                    LabeledContent("Power source") {
                        Text(powerDescription).foregroundStyle(.secondary)
                    }
                }
            }

            Section("General") {
                Toggle("Start \(AppInfo.name) at login", isOn: Binding(
                    get: { state.system.loginItem.isEnabled },
                    set: { state.setStartAtLogin($0) }))
                if state.system.loginItem.requiresUserApproval {
                    Text("macOS is waiting for approval in System Settings › General › Login Items.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Toggle("Show in menu bar", isOn: Binding(
                    get: { state.settings.showInMenuBar },
                    set: { v in state.preferences.update { $0.showInMenuBar = v } }))
            }

            Section("Status") {
                LabeledContent("Playback", value: statusDescription)
                LabeledContent("Displays", value: "\(state.displayManager.displays.count) active")
            }

            Section("About") {
                LabeledContent("Version", value: "\(AppInfo.version) (\(AppInfo.build))")
                LabeledContent("macOS", value: OSVersion.current.description)
                LabeledContent("Library") {
                    Button(AppDirectories.root.path) {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: AppDirectories.root.path)
                    }
                    .buttonStyle(.link)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                Text("Everything stays on this Mac. \(AppInfo.name) has no network code, no account and no analytics.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func binding<V>(_ keyPath: WritableKeyPath<PlaybackSettings, V>) -> Binding<V> {
        Binding(
            get: { state.settings.playback[keyPath: keyPath] },
            set: { v in state.preferences.update { $0.playback[keyPath: keyPath] = v } })
    }

    private var powerDescription: String {
        let source = state.system.power.isOnBattery ? "Battery" : "AC power"
        let level = state.system.power.batteryPercentage.map { " · \($0)%" } ?? ""
        let lpm = state.system.power.isLowPowerMode ? " · Low Power Mode" : ""
        return source + level + lpm
    }

    private var statusDescription: String {
        if state.engine.suppressions.isEmpty {
            return state.engine.contexts.isEmpty ? "Idle — no wallpaper assigned" : "Playing"
        }
        let reasons = state.engine.suppressions.map(\.label).sorted().joined(separator: ", ")
        return "Paused (\(reasons))"
    }
}

extension WallpaperEngine.Suppression {
    var label: String {
        switch self {
        case .userPaused: return "paused by you"
        case .lowPower: return "Low Power Mode"
        case .battery: return "on battery"
        case .fullScreenApp: return "full-screen app"
        case .screenLocked: return "screen locked"
        case .asleep: return "display asleep"
        }
    }
}

import SwiftUI

struct LockScreenView: View {
    @Environment(AppState.self) private var state
    @State private var showRestoreConfirm = false
    @State private var showApplyConfirm = false

    private var controller: LockScreenController { state.lockScreen }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                statusBanner
                if let warning = controller.warning {
                    calloutRow(icon: "exclamationmark.triangle", tint: .orange, text: warning)
                }
                wallpaperSelection
                actions
                fileVaultNote
                if let report = controller.report { storeDetails(report) }
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .task { await controller.refresh() }
        .alert(item: Binding(get: { controller.lastError }, set: { _ in })) { err in
            Alert(title: Text(err.title), message: Text(err.message), dismissButton: .default(Text("OK")))
        }
        .confirmationDialog("Apply this video to your Lock Screen?", isPresented: $showApplyConfirm, titleVisibility: .visible) {
            Button("Apply") { Task { await controller.apply() } }
        } message: {
            Text("\(AppInfo.name) will back up the two macOS wallpaper files it changes, then add your video as a new Aerial wallpaper. Apple's own wallpaper files are never overwritten, and Restore puts everything back.")
        }
        .confirmationDialog("Restore Apple's Lock Screen wallpaper?", isPresented: $showRestoreConfirm, titleVisibility: .visible) {
            Button("Restore", role: .destructive) { Task { await controller.restore() } }
        } message: {
            Text("The backed-up wallpaper files are restored and verified, and the video \(AppInfo.name) added is removed.")
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var statusBanner: some View {
        switch controller.status {
        case .checking:
            calloutRow(icon: "hourglass", tint: .secondary, text: "Checking the macOS wallpaper store…")
        case .unsupported(let reason):
            calloutRow(icon: "xmark.octagon", tint: .red, text: reason)
        case .needsAttention(let reason):
            calloutRow(icon: "exclamationmark.triangle", tint: .orange, text: reason)
        case .ready:
            calloutRow(icon: "checkmark.seal", tint: .green,
                       text: "Ready. macOS \(OSVersion.current.description) is supported and the wallpaper store looks healthy.")
        case .installed(_, let at):
            calloutRow(icon: "lock.display", tint: .green,
                       text: "Your video is installed as the Lock Screen wallpaper. Applied \(at.formatted(date: .abbreviated, time: .shortened)).")
        }
    }

    private var wallpaperSelection: some View {
        GroupBox("Wallpapers") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Use the same video as the Desktop", isOn: Binding(
                    get: { state.settings.lockScreen.useDesktopWallpaper },
                    set: { v in state.preferences.update { $0.lockScreen.useDesktopWallpaper = v } }))

                HStack(alignment: .top, spacing: 20) {
                    wallpaperTile(title: "Desktop", asset: state.desktopAsset)
                    wallpaperTile(title: "Lock Screen", asset: controller.selectedAsset)
                }

                if !state.settings.lockScreen.useDesktopWallpaper {
                    Picker("Lock Screen video", selection: Binding(
                        get: { state.settings.lockScreen.assetID },
                        set: { v in state.preferences.update { $0.lockScreen.assetID = v } })) {
                        Text("None").tag(UUID?.none)
                        ForEach(state.library.assets) { Text($0.displayName).tag(UUID?.some($0.id)) }
                    }
                }
            }
            .padding(6)
        }
    }

    private func wallpaperTile(title: String, asset: WallpaperAsset?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            PosterImage(url: asset.flatMap { state.library.thumbnailURL(for: $0) })
                .frame(width: 190, height: 107)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
            Text(asset?.displayName ?? "None")
                .font(.callout).lineLimit(1).truncationMode(.middle)
                .frame(width: 190, alignment: .leading)
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button("Apply to Lock Screen") { showApplyConfirm = true }
                .buttonStyle(.borderedProminent)
                .disabled(!controller.isSupported || controller.selectedAsset == nil || controller.isBusy)

            Button("Restore Apple Wallpaper") { showRestoreConfirm = true }
                .disabled(controller.installation == nil || controller.isBusy)

            if controller.isBusy {
                ProgressView().controlSize(.small)
                Text(controller.busyDescription).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var fileVaultNote: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Label("What this does and does not cover", systemImage: "info.circle")
                    .font(.callout.weight(.medium))
                Text("Covered: the Lock Screen you see after locking your Mac or waking it while you are logged in.")
                    .font(.callout)
                Text("Not covered: the FileVault login screen after a restart or shutdown. That screen runs before your account is unlocked, so it cannot read your video. \(AppInfo.name) does not try to change it.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private func storeDetails(_ report: AerialStoreReport) -> some View {
        GroupBox("macOS wallpaper store") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 3) {
                detail("Aerial wallpapers", "\(report.assetCount)")
                detail("Downloaded videos", "\(report.downloadedAssetIDs.count)")
                detail("Media key", report.mediaKey ?? "–")
                detail("Added by \(AppInfo.name)", "\(report.liveCanvasAssetIDs.count)")
                let foreign = Set(report.injectedAssetIDs).subtracting(report.liveCanvasAssetIDs).count
                detail("Added by other apps", "\(foreign)")
                detail("Apple entries redirected", "\(report.modifiedAppleAssetIDs.count)")
            }
            .font(.callout)
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
        }
    }

    private func calloutRow(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

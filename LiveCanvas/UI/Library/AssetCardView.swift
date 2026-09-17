import SwiftUI

struct AssetCardView: View {
    @Environment(AppState.self) private var state
    let asset: WallpaperAsset

    @State private var isHovering = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var showDeleteConfirm = false

    private var isPreviewing: Bool { state.preview.currentAssetID == asset.id && isHovering }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                PosterImage(url: state.library.thumbnailURL(for: asset))
                if isPreviewing {
                    PlayerLayerView(player: state.preview.player, gravity: .resizeAspectFill)
                        .transition(.opacity)
                }
                badges
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
            .animation(.easeInOut(duration: 0.15), value: isPreviewing)

            Text(asset.displayName)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("\(asset.resolutionLabel)  ·  \(asset.durationLabel)  ·  \(asset.fileSizeLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture { state.presentedAsset = asset }
        .draggable(WallpaperAssetTransfer(id: asset.id)) {
            PosterImage(url: state.library.thumbnailURL(for: asset))
                .frame(width: 160, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .onHover { hovering in
            isHovering = hovering
            hoverTask?.cancel()
            if hovering {
                hoverTask = Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled, isHovering else { return }
                    state.preview.play(asset: asset, url: state.library.mediaURL(for: asset))
                }
            } else {
                state.preview.stop(if: asset.id)
            }
        }
        .contextMenu { menu }
        .confirmationDialog("Delete “\(asset.displayName)”?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { state.delete(asset) }
        } message: {
            Text("The managed copy in the library will be removed. Your original file is not affected.")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(asset.displayName), \(asset.resolutionLabel), \(asset.durationLabel)")
    }

    private var badges: some View {
        VStack {
            HStack(spacing: 4) {
                Spacer()
                badge(asset.qualityLabel)
                if asset.dynamicRange == .hdr { badge("HDR") }
                if asset.hasAudio { badge(systemImage: "speaker.wave.2") }
            }
            Spacer()
            HStack {
                if state.desktopAsset?.id == asset.id { badge(systemImage: "desktopcomputer") }
                if state.lockScreenAsset?.id == asset.id && state.settings.lockScreen.enabled { badge(systemImage: "lock") }
                Spacer()
            }
        }
        .padding(6)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(.black.opacity(0.55), in: Capsule())
            .foregroundStyle(.white)
    }

    private func badge(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.caption2.weight(.semibold))
            .padding(4)
            .background(.black.opacity(0.55), in: Circle())
            .foregroundStyle(.white)
    }

    @ViewBuilder
    private var menu: some View {
        Button("Preview") { state.presentedAsset = asset }
        Divider()
        Button("Set as Desktop Wallpaper") { state.setDesktop(asset) }
        Button("Set as Lock Screen Wallpaper") { state.setLockScreen(asset) }
        Button("Set for Both") { state.setBoth(asset) }
        Divider()
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([state.library.mediaURL(for: asset)])
        }
        Divider()
        Button("Delete…", role: .destructive) { showDeleteConfirm = true }
    }
}

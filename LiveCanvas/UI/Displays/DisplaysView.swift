import SwiftUI
import UniformTypeIdentifiers

struct DisplaysView: View {
    @Environment(AppState.self) private var state

    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 320, maximum: 460), spacing: 20)] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                modeControl
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ForEach(state.displayManager.displays) { display in
                        DisplayCardView(display: display)
                    }
                }
            }
            .padding(20)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    state.displayManager.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Re-read the connected displays")
            }
        }
    }

    private var modeControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("", selection: Binding(
                get: { state.settings.desktop.useSameOnAllDisplays },
                set: { v in state.preferences.update { $0.desktop.useSameOnAllDisplays = v } })) {
                Text("Same wallpaper on all displays").tag(true)
                Text("Configure each display").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)

            Text(state.settings.desktop.useSameOnAllDisplays
                 ? "Every display shows the wallpaper you set in the Library."
                 : "Drop a wallpaper onto a display, or pick one from its menu.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct DisplayCardView: View {
    @Environment(AppState.self) private var state
    let display: DisplayConfiguration
    @State private var isTargeted = false

    private var assignment: WallpaperAssignment? {
        state.settings.desktop.assignment(for: display.id)
    }

    private var asset: WallpaperAsset? { state.library.asset(id: assignment?.assetID) }

    private var fitMode: FitMode {
        assignment?.fitMode ?? state.settings.playback.defaultFitMode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            preview
            header
            controls
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                              lineWidth: isTargeted ? 2 : 0.5)
        }
        .dropDestination(for: WallpaperAssetTransfer.self) { items, _ in
            guard let first = items.first, let asset = state.library.asset(id: first.id) else { return false }
            state.assign(asset, to: display)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    /// Screen-shaped preview so the user sees how the fit mode will crop or letterbox.
    private var preview: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle().fill(.black)
                if let asset, let thumb = state.library.thumbnailURL(for: asset) {
                    PosterImage(url: thumb, contentMode: previewContentMode, naturalAspect: asset.aspectRatio)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.badge.plus").font(.title2)
                        Text("Drop a wallpaper here").font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(display.aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
    }

    private var previewContentMode: PosterImage.Mode {
        switch fitMode {
        case .fill: return .fill
        case .fit: return .fit
        case .stretch: return .stretch
        case .original: return .fit
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                    .foregroundStyle(.secondary)
                Text(display.name).font(.headline).lineLimit(1)
                if display.isMain {
                    Text("Main")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
            }
            Text("\(display.pixelResolutionLabel)  ·  Scale: \(display.scaleLabel)  ·  \(Int(display.frame.width)) × \(Int(display.frame.height)) pt")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 8) {
            Menu {
                Button("None") { state.clearAssignment(for: display) }
                Divider()
                ForEach(state.library.assets) { candidate in
                    Button(candidate.displayName) { state.assign(candidate, to: display) }
                }
            } label: {
                Text(asset?.displayName ?? "No wallpaper")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker("", selection: Binding(
                get: { fitMode },
                set: { state.setFitMode($0, for: display) })) {
                ForEach(FitMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .labelsHidden()
            .frame(width: 110)
            .disabled(asset == nil)
            .help(fitMode.help)
        }
        .disabled(state.settings.desktop.useSameOnAllDisplays && asset == nil && state.library.assets.isEmpty)
    }
}

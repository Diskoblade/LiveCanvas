import SwiftUI

struct AssetDetailView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let asset: WallpaperAsset

    @State private var name: String = ""
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            PlayerLayerView(player: state.preview.player, gravity: .resizeAspect)
                .background(.black)
                .frame(minHeight: 320)
                .aspectRatio(max(asset.aspectRatio, 1.2), contentMode: .fit)

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                        .onSubmit { commitRename() }
                    metadata
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Button("Set as Desktop") { state.setDesktop(asset) }
                    Button("Set as Lock Screen") { state.setLockScreen(asset) }
                    Button("Set for Both") { state.setBoth(asset) }
                    Spacer()
                    Button("Delete…", role: .destructive) { showDeleteConfirm = true }
                }
                .controlSize(.regular)
                .frame(width: 160)
            }
            .padding(20)
        }
        .frame(minWidth: 720, idealWidth: 820)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { commitRename(); dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .onAppear {
            name = asset.displayName
            state.preview.play(asset: asset, url: state.library.mediaURL(for: asset))
        }
        .onDisappear {
            state.preview.stop(if: asset.id)
        }
        .confirmationDialog("Delete “\(asset.displayName)”?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { state.delete(asset); dismiss() }
        } message: {
            Text("The managed copy in the library will be removed. Your original file is not affected.")
        }
    }

    private var metadata: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            row("Resolution", "\(asset.resolutionLabel) (\(asset.qualityLabel))")
            row("Duration", asset.durationLabel)
            row("Frame rate", asset.frameRateLabel)
            row("Codec", "\(asset.codec.displayName) (\(asset.codecFourCC))")
            row("Dynamic range", asset.dynamicRange.displayName)
            row("Audio", asset.hasAudio ? "Yes (muted on desktop unless enabled)" : "None")
            row("File size", asset.fileSizeLabel)
            row("Imported", asset.dateImported.formatted(date: .abbreviated, time: .shortened))
            if let src = asset.sourceURL { row("Original", src.path) }
        }
        .font(.callout)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
        }
    }

    private func commitRename() {
        if name != asset.displayName { state.library.rename(asset, to: name) }
    }
}

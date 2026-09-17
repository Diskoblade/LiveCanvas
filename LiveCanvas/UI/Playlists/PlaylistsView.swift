import SwiftUI

struct PlaylistsView: View {
    @Environment(AppState.self) private var state
    @State private var selection: UUID?
    @State private var renaming: UUID?
    @State private var draftName = ""

    private var playlists: [Playlist] { state.settings.playlists }

    var body: some View {
        Group {
            if playlists.isEmpty {
                empty
            } else {
                HSplitView {
                    list.frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
                    detail.frame(minWidth: 380)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { addPlaylist() } label: { Label("New Playlist", systemImage: "plus") }
                    .help("Create a playlist")
            }
        }
        .onAppear { if selection == nil { selection = playlists.first?.id } }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("No Playlists", systemImage: "list.bullet.rectangle")
        } description: {
            Text("A playlist rotates through several wallpapers on a schedule.")
        } actions: {
            Button("New Playlist") { addPlaylist() }
        }
    }

    // MARK: List

    private var list: some View {
        List(selection: $selection) {
            ForEach(playlists) { playlist in
                HStack(spacing: 6) {
                    Image(systemName: state.settings.desktop.referencesPlaylist(playlist.id)
                          ? "play.circle.fill" : "list.bullet")
                        .foregroundStyle(state.settings.desktop.referencesPlaylist(playlist.id) ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(playlist.name).lineLimit(1)
                        Text(Pluralize.count(playlist.assetIDs.count, "wallpaper"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tag(playlist.id)
                .contextMenu {
                    Button("Set as Desktop Wallpaper") { state.setDesktopPlaylist(playlist) }
                        .disabled(playlist.assetIDs.isEmpty)
                    Button("Rename…") { beginRename(playlist) }
                    Divider()
                    Button("Delete", role: .destructive) { delete(playlist) }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let playlist = playlists.first(where: { $0.id == selection }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(playlist)
                    settings(playlist)
                    members(playlist)
                    addMenu(playlist)
                }
                .padding(20)
            }
        } else {
            ContentUnavailableView("Select a Playlist", systemImage: "list.bullet.rectangle")
        }
    }

    private func header(_ playlist: Playlist) -> some View {
        HStack(alignment: .firstTextBaseline) {
            if renaming == playlist.id {
                TextField("Name", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .font(.title2)
                    .frame(maxWidth: 320)
                    .onSubmit { commitRename(playlist) }
            } else {
                Text(playlist.name).font(.title2)
                Button { beginRename(playlist) } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless)
                    .help("Rename")
            }
            Spacer()
            Button("Set as Desktop Wallpaper") { state.setDesktopPlaylist(playlist) }
                .disabled(playlist.assetIDs.isEmpty)
        }
    }

    private func settings(_ playlist: Playlist) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Order", selection: binding(playlist, \.mode)) {
                    ForEach(PlaylistMode.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)

                Picker("Change every", selection: binding(playlist, \.interval)) {
                    ForEach(PlaylistInterval.presets, id: \.self) { Text($0.displayName).tag($0) }
                }
                .frame(maxWidth: 260)

                if playlist.assetIDs.count < 2 {
                    Text("Add at least two wallpapers for the playlist to rotate.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if state.settings.desktop.referencesPlaylist(playlist.id) {
                    Text(nextChangeDescription(playlist))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(6)
        }
    }

    private func members(_ playlist: Playlist) -> some View {
        GroupBox("Wallpapers") {
            if playlist.assetIDs.isEmpty {
                Text("Empty. Add wallpapers from your library below.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(playlist.assetIDs.enumerated()), id: \.offset) { index, assetID in
                        if let asset = state.library.asset(id: assetID) {
                            memberRow(playlist, asset: asset, index: index)
                            if index < playlist.assetIDs.count - 1 { Divider() }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func memberRow(_ playlist: Playlist, asset: WallpaperAsset, index: Int) -> some View {
        let isPlaying = state.settings.desktop.referencesPlaylist(playlist.id)
            && state.playlists.resolveAsset(for: .playlist(playlist.id))?.id == asset.id
        return HStack(spacing: 10) {
            PosterImage(url: state.library.thumbnailURL(for: asset))
                .frame(width: 64, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            VStack(alignment: .leading, spacing: 1) {
                Text(asset.displayName).lineLimit(1)
                Text("\(asset.resolutionLabel)  ·  \(asset.durationLabel)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isPlaying {
                Label("Playing", systemImage: "play.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Color.accentColor)
                    .help("Currently on screen")
            }
            Button { move(playlist, from: index, by: -1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless).disabled(index == 0)
            Button { move(playlist, from: index, by: 1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless).disabled(index == playlist.assetIDs.count - 1)
            Button { remove(playlist, at: index) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help("Remove from playlist")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
    }

    private func addMenu(_ playlist: Playlist) -> some View {
        let candidates = state.library.assets.filter { !playlist.assetIDs.contains($0.id) }
        return Menu {
            if candidates.isEmpty {
                Text("Every wallpaper is already in this playlist")
            } else {
                ForEach(candidates) { asset in
                    Button(asset.displayName) { add(playlist, asset: asset) }
                }
            }
        } label: {
            Label("Add Wallpaper", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(candidates.isEmpty)
    }

    // MARK: Helpers

    private func nextChangeDescription(_ playlist: Playlist) -> String {
        let st = state.settings.playlistState(playlist.id)
        guard let next = PlaylistRotation.nextChange(playlist: playlist, state: st, now: Date()) else {
            return "This playlist does not rotate."
        }
        return "Next change \(next.formatted(date: .omitted, time: .shortened))."
    }

    private func binding<V>(_ playlist: Playlist, _ keyPath: WritableKeyPath<Playlist, V>) -> Binding<V> {
        Binding(
            get: { (playlists.first { $0.id == playlist.id } ?? playlist)[keyPath: keyPath] },
            set: { v in mutate(playlist.id) { $0[keyPath: keyPath] = v } })
    }

    private func mutate(_ id: UUID, _ body: (inout Playlist) -> Void) {
        state.preferences.update { s in
            guard let i = s.playlists.firstIndex(where: { $0.id == id }) else { return }
            body(&s.playlists[i])
        }
        state.playlists.playlistDidChange(id)
    }

    private func addPlaylist() {
        let existing = Set(playlists.map(\.name))
        var name = "New Playlist"
        var n = 2
        while existing.contains(name) { name = "New Playlist \(n)"; n += 1 }
        let playlist = Playlist(name: name)
        state.preferences.update { $0.playlists.append(playlist) }
        selection = playlist.id
        beginRename(playlist)
    }

    private func delete(_ playlist: Playlist) {
        state.preferences.update { s in
            s.playlists.removeAll { $0.id == playlist.id }
            s.removePlaylistState(playlist.id)
            s.desktop.removePlaylist(playlist.id)
        }
        if selection == playlist.id { selection = playlists.first?.id }
    }

    private func beginRename(_ playlist: Playlist) {
        draftName = playlist.name
        renaming = playlist.id
    }

    private func commitRename(_ playlist: Playlist) {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { mutate(playlist.id) { $0.name = trimmed } }
        renaming = nil
    }

    private func add(_ playlist: Playlist, asset: WallpaperAsset) {
        mutate(playlist.id) { $0.assetIDs.append(asset.id) }
    }

    private func remove(_ playlist: Playlist, at index: Int) {
        mutate(playlist.id) { p in
            guard p.assetIDs.indices.contains(index) else { return }
            p.assetIDs.remove(at: index)
        }
    }

    private func move(_ playlist: Playlist, from index: Int, by offset: Int) {
        mutate(playlist.id) { p in
            let target = index + offset
            guard p.assetIDs.indices.contains(index), p.assetIDs.indices.contains(target) else { return }
            p.assetIDs.swapAt(index, target)
        }
    }
}

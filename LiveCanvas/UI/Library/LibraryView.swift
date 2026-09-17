import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(AppState.self) private var state
    @State private var isDropTargeted = false
    @State private var sort: SortOrder = .newest

    enum SortOrder: String, CaseIterable, Identifiable {
        case newest, name, duration, size
        var id: String { rawValue }
        var title: String {
            switch self {
            case .newest: return "Date Added"
            case .name: return "Name"
            case .duration: return "Duration"
            case .size: return "File Size"
            }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16)]

    var body: some View {
        Group {
            if state.library.assets.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(sortedAssets) { asset in
                            AssetCardView(asset: asset)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .background(Color.accentColor.opacity(0.06))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let supported = urls.filter(VideoAssetManager.isSupported)
            guard !supported.isEmpty else { return false }
            Task { await state.library.importFiles(supported) }
            return true
        } isTargeted: { isDropTargeted = $0 }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if state.library.importsInProgress > 0 {
                    ProgressView().controlSize(.small)
                }
                Picker("Sort", selection: $sort) {
                    ForEach(SortOrder.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .help("Sort order")
                Button {
                    state.presentImportPanel()
                } label: {
                    Label("Add Wallpaper", systemImage: "plus")
                }
                .help("Add MP4, MOV or M4V files to the library")
            }
        }
    }

    private var sortedAssets: [WallpaperAsset] {
        switch sort {
        case .newest: return state.library.assets.sorted { $0.dateImported > $1.dateImported }
        case .name: return state.library.assets.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        case .duration: return state.library.assets.sorted { $0.duration > $1.duration }
        case .size: return state.library.assets.sorted { $0.fileSize > $1.fileSize }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Wallpapers", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("Drag MP4, MOV or M4V files here, or click Add Wallpaper.")
        } actions: {
            Button("Add Wallpaper…") { state.presentImportPanel() }
                .keyboardShortcut("o", modifiers: .command)
        }
    }
}

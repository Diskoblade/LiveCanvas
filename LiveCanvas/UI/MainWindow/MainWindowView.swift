import SwiftUI

struct MainWindowView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $state.selectedSection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            detail
                .navigationTitle(state.selectedSection.title)
        }
        .sheet(item: $state.presentedAsset) { asset in
            AssetDetailView(asset: asset)
                .environment(state)
        }
        .alert(item: $state.presentedError) { err in
            Alert(title: Text(err.title), message: Text(err.message), dismissButton: .default(Text("OK")))
        }
        .onChange(of: state.library.lastError?.id) { _, _ in
            if let e = state.library.lastError { state.presentedError = e }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch state.selectedSection {
        case .library: LibraryView()
        case .displays: DisplaysView()
        case .lockScreen: LockScreenView()
        case .playlists: PlaylistsView()
        case .settings: SettingsView()
        }
    }
}

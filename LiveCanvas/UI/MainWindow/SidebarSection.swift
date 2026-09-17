import Foundation

enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case library, displays, lockScreen, playlists, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return "Library"
        case .displays: return "Displays"
        case .lockScreen: return "Lock Screen"
        case .playlists: return "Playlists"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .library: return "photo.on.rectangle.angled"
        case .displays: return "display.2"
        case .lockScreen: return "lock.display"
        case .playlists: return "list.bullet.rectangle"
        case .settings: return "gearshape"
        }
    }
}

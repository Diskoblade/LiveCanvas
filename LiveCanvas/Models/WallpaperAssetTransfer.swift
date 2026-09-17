import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// Lightweight drag payload: just the asset's identifier. The receiving view resolves it
/// against the library, so no file data is copied during a drag.
struct WallpaperAssetTransfer: Codable, Transferable, Sendable {
    let id: UUID

    static let contentType = UTType(exportedAs: "com.rahul.livecanvas.wallpaper-asset")

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: contentType)
    }
}

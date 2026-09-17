import Foundation

/// On-disk representation of library.json.
struct LibraryDocument: Codable, Equatable, Sendable {
    static let currentVersion = 1
    var version: Int = LibraryDocument.currentVersion
    var assets: [WallpaperAsset] = []
}

/// JSON persistence for the library. Pure I/O, no state.
struct LibraryStore: Sendable {
    var fileURL: URL

    init(fileURL: URL = AppDirectories.libraryFile) {
        self.fileURL = fileURL
    }

    func load() throws -> LibraryDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return LibraryDocument() }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONCoding.decoder()
        return try decoder.decode(LibraryDocument.self, from: data)
    }

    func save(_ document: LibraryDocument) throws {
        let encoder = JSONCoding.encoder()
        let data = try encoder.encode(document)
        try AtomicFileWriter.write(data, to: fileURL)
    }
}

import Foundation

/// Minimal read-only USTAR reader. Used to read Apple's pristine `entries.json` out of
/// `manifest.tar` without shelling out or extracting anything to disk.
enum TarReader {
    private static let blockSize = 512

    static func extractFile(named name: String, from tarURL: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: tarURL)
        defer { try? handle.close() }

        var offset: UInt64 = 0
        while true {
            try handle.seek(toOffset: offset)
            guard let header = try handle.read(upToCount: blockSize), header.count == blockSize else { break }
            if header.allSatisfy({ $0 == 0 }) { break }             // end-of-archive

            let entryName = string(header, at: 0, length: 100)
            guard !entryName.isEmpty else { break }
            let size = octal(header, at: 124, length: 12)
            let typeFlag = header[156]

            let dataOffset = offset + UInt64(blockSize)
            // '0' and '\0' are regular files; everything else (dirs, links) is skipped.
            if (typeFlag == 0x30 || typeFlag == 0x00), entryName == name || entryName.hasSuffix("/" + name) {
                try handle.seek(toOffset: dataOffset)
                guard let data = try handle.read(upToCount: Int(size)), data.count == Int(size) else {
                    throw LiveCanvasError.wallpaperStoreNotInitialized("manifest.tar entry \(name) is truncated.")
                }
                return data
            }

            let padded = (size + UInt64(blockSize) - 1) / UInt64(blockSize) * UInt64(blockSize)
            offset = dataOffset + padded
        }
        throw LiveCanvasError.wallpaperStoreNotInitialized("manifest.tar does not contain \(name).")
    }

    private static func string(_ data: Data, at offset: Int, length: Int) -> String {
        let slice = data.subdata(in: offset..<(offset + length))
        let trimmed = slice.prefix { $0 != 0 }
        return String(data: trimmed, encoding: .utf8)?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    private static func octal(_ data: Data, at offset: Int, length: Int) -> UInt64 {
        let text = string(data, at: offset, length: length)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
        return UInt64(text, radix: 8) ?? 0
    }
}

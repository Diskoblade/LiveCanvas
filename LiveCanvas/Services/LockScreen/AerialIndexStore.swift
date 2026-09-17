import Foundation

/// Reads and writes the `Idle` (Lock Screen) choice inside `Store/Index.plist`.
///
/// The file is owned by macOS `WallpaperAgent`. Every write preserves the entire document
/// and changes only the nested `Configuration` blob of `Idle` choices whose provider is
/// the Aerial provider. Nothing else in the plist is touched.
struct AerialIndexStore: Sendable {
    static let aerialProvider = "com.apple.wallpaper.choice.aerials"

    var indexFile: URL

    init(indexFile: URL) { self.indexFile = indexFile }

    struct Snapshot: Sendable, Equatable {
        /// assetID currently selected for the Lock Screen, per display UUID.
        var assetIDsByDisplay: [String: String]
        /// The distinct asset IDs in use.
        var assetIDs: Set<String> { Set(assetIDsByDisplay.values) }
        /// True when every Idle node uses the Aerial provider.
        var allIdleNodesAreAerial: Bool
    }

    // MARK: Read

    func readPlist() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: indexFile.path) else {
            throw LiveCanvasError.wallpaperStoreNotInitialized("Store/Index.plist does not exist. Choose any wallpaper in System Settings once, then try again.")
        }
        let data = try Data(contentsOf: indexFile)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw LiveCanvasError.wallpaperStoreNotInitialized("Store/Index.plist is not a property list dictionary.")
        }
        return plist
    }

    func snapshot() throws -> Snapshot {
        let plist = try readPlist()
        var byDisplay: [String: String] = [:]
        var allAerial = true
        var sawIdle = false

        for (displayID, value) in (plist["Displays"] as? [String: Any]) ?? [:] {
            guard let display = value as? [String: Any],
                  let idle = display["Idle"] as? [String: Any],
                  let content = idle["Content"] as? [String: Any],
                  let choices = content["Choices"] as? [[String: Any]],
                  let first = choices.first else { continue }
            sawIdle = true
            guard (first["Provider"] as? String) == Self.aerialProvider else {
                allAerial = false
                continue
            }
            if let data = first["Configuration"] as? Data, let assetID = Self.assetID(fromConfiguration: data) {
                byDisplay[displayID] = assetID
            }
        }
        return Snapshot(assetIDsByDisplay: byDisplay, allIdleNodesAreAerial: sawIdle && allAerial)
    }

    /// Decodes the nested binary plist `{ "assetID": "<uuid>" }`.
    static func assetID(fromConfiguration data: Data) -> String? {
        guard let nested = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return nested["assetID"] as? String
    }

    static func configuration(forAssetID assetID: String) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: ["assetID": assetID], format: .binary, options: 0)
    }

    // MARK: Write

    /// Points every Aerial `Idle` choice at `assetID`. Returns the number of displays changed.
    /// Idle nodes that use a different provider are left alone.
    @discardableResult
    func setLockScreenAsset(_ assetID: String) throws -> Int {
        var plist = try readPlist()
        let configuration = try Self.configuration(forAssetID: assetID)
        var changed = 0

        func rewrite(_ node: inout [String: Any]) -> Bool {
            guard var content = node["Content"] as? [String: Any],
                  var choices = content["Choices"] as? [[String: Any]],
                  !choices.isEmpty,
                  (choices[0]["Provider"] as? String) == Self.aerialProvider else { return false }
            choices[0]["Configuration"] = configuration
            content["Choices"] = choices
            node["Content"] = content
            node["LastSet"] = Date()
            node["LastUse"] = Date()
            return true
        }

        if var displays = plist["Displays"] as? [String: Any] {
            for (displayID, value) in displays {
                guard var display = value as? [String: Any], var idle = display["Idle"] as? [String: Any] else { continue }
                if rewrite(&idle) {
                    display["Idle"] = idle
                    displays[displayID] = display
                    changed += 1
                }
            }
            plist["Displays"] = displays
        }

        // Keep the system default in step so a newly attached display matches.
        if var systemDefault = plist["SystemDefault"] as? [String: Any],
           var idle = systemDefault["Idle"] as? [String: Any] {
            if rewrite(&idle) {
                systemDefault["Idle"] = idle
                plist["SystemDefault"] = systemDefault
            }
        }

        guard changed > 0 else {
            throw LiveCanvasError.lockScreenUnavailable("No display is currently using an Aerial Lock Screen wallpaper. Open System Settings › Wallpaper, choose any Aerial under Lock Screen, then apply again.")
        }

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        try AtomicFileWriter.write(data, to: indexFile)
        Log.lockscreen.info("Index.plist updated for \(changed) display(s)")
        return changed
    }
}

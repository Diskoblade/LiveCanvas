import Foundation

/// Deep check: does each downloaded Aerial video actually match what the manifest says it
/// should be? A tool that overwrites an Apple `.mov` in place leaves the manifest untouched,
/// so a URL-only comparison cannot see it. The media key itself carries the expected
/// profile (for example `url-4K-SDR-240FPS`), which gives a data-driven expectation to
/// check against rather than a hard-coded one.
struct AerialMediaAudit: Sendable {

    struct Finding: Sendable, Equatable, Identifiable {
        var id: String { assetID }
        var assetID: String
        var name: String
        var expected: String
        var actual: String
        var reason: Reason

        enum Reason: String, Sendable {
            /// The file is far larger than the resolution class the manifest declares.
            case resolutionExceedsDeclaredClass
            /// The manifest points at Apple's CDN but the file is not the profile Apple ships.
            case codecUnexpectedForAppleAsset
        }
    }

    /// Longest edge implied by the resolution token in a media key, e.g. "4K" → 3840.
    /// Unknown tokens return nil so the audit stays silent rather than guessing.
    static func declaredLongEdge(fromMediaKey key: String) -> Int? {
        let upper = key.uppercased()
        // Ordered longest-first so "16K" is not matched by "1K".
        let table: [(String, Int)] = [("16K", 15360), ("12K", 12288), ("8K", 7680), ("6K", 6144),
                                      ("5K", 5120), ("4K", 3840), ("2K", 2048), ("1080", 1920), ("720", 1280)]
        for (token, edge) in table where upper.contains(token) { return edge }
        return nil
    }

    var locator: AerialStoreLocator
    var metadata = VideoMetadataService()

    /// Probes the downloaded videos of Apple-provided assets and reports mismatches.
    /// `pristineIDs` comes from Apple's own manifest.tar, so only genuine Apple assets
    /// are judged; entries added by LiveCanvas or another tool are skipped.
    func auditAppleAssets(manifest: AerialManifest, pristineIDs: Set<String>) async -> [Finding] {
        guard let declaredEdge = Self.declaredLongEdge(fromMediaKey: manifest.mediaKey) else { return [] }
        var findings: [Finding] = []

        for asset in manifest.assets {
            guard pristineIDs.contains(asset.id) else { continue }           // Apple's own entry
            guard !asset.isLocalMedia else { continue }                      // already reported as redirected
            let file = locator.videoURL(for: asset.id)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            guard let probe = try? await metadata.probe(file) else { continue }

            let longEdge = max(probe.pixelWidth, probe.pixelHeight)
            // A tolerance keeps legitimate variation (e.g. 3840 vs 4096) from being flagged.
            if longEdge > Int(Double(declaredEdge) * 1.25) {
                findings.append(Finding(
                    assetID: asset.id, name: asset.name,
                    expected: "≤ \(declaredEdge) px (\(manifest.mediaKey))",
                    actual: "\(probe.pixelWidth) × \(probe.pixelHeight) \(probe.codec.displayName)",
                    reason: .resolutionExceedsDeclaredClass))
            }
        }
        return findings
    }
}

import Foundation
import AVFoundation
import CoreMedia

/// Result of probing a video file. Value type so it can cross actor boundaries.
struct VideoProbe: Sendable, Equatable {
    var duration: TimeInterval
    var pixelWidth: Int
    var pixelHeight: Int
    var frameRate: Double
    var codec: VideoCodec
    var codecFourCC: String
    var dynamicRange: DynamicRange
    var hasAudio: Bool
    var isPlayable: Bool
}

/// Reads technical metadata using AVFoundation only (no manual frame decoding).
struct VideoMetadataService: Sendable {
    func probe(_ url: URL) async throws -> VideoProbe {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let (duration, isPlayable) = try await asset.load(.duration, .isPlayable)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = videoTracks.first else {
            throw LiveCanvasError.videoUndecodable("\(url.lastPathComponent) contains no video track.")
        }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        let (naturalSize, transform, nominalFrameRate, formatDescriptions) =
            try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions)

        let oriented = naturalSize.applying(transform)
        let width = Int(abs(oriented.width).rounded())
        let height = Int(abs(oriented.height).rounded())
        guard width > 0, height > 0 else {
            throw LiveCanvasError.videoUndecodable("\(url.lastPathComponent) reports a zero-sized video track.")
        }

        var codec = VideoCodec.other
        var fourCC = "????"
        var range = DynamicRange.unknown
        if let fd = formatDescriptions.first {
            let subtype = CMFormatDescriptionGetMediaSubType(fd)
            fourCC = Self.fourCCString(subtype)
            switch subtype {
            case kCMVideoCodecType_H264: codec = .h264
            case kCMVideoCodecType_HEVC, kCMVideoCodecType_HEVCWithAlpha: codec = .hevc
            case kCMVideoCodecType_AppleProRes422, kCMVideoCodecType_AppleProRes422HQ,
                 kCMVideoCodecType_AppleProRes422LT, kCMVideoCodecType_AppleProRes422Proxy,
                 kCMVideoCodecType_AppleProRes4444, kCMVideoCodecType_AppleProRes4444XQ,
                 kCMVideoCodecType_AppleProResRAW, kCMVideoCodecType_AppleProResRAWHQ:
                codec = .proRes
            default: codec = .other
            }
            range = Self.dynamicRange(from: fd)
        }

        let seconds = CMTimeGetSeconds(duration)
        return VideoProbe(
            duration: seconds.isFinite ? seconds : 0,
            pixelWidth: width,
            pixelHeight: height,
            frameRate: Double(nominalFrameRate),
            codec: codec,
            codecFourCC: fourCC,
            dynamicRange: range,
            hasAudio: !audioTracks.isEmpty,
            isPlayable: isPlayable
        )
    }

    static func dynamicRange(from fd: CMFormatDescription) -> DynamicRange {
        let transfer = CMFormatDescriptionGetExtension(fd, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String
        let primaries = CMFormatDescriptionGetExtension(fd, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries) as? String
        if let t = transfer {
            if t == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String) ||
                t == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String) {
                return .hdr
            }
            return .sdr
        }
        if let p = primaries, p == (kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String) {
            return .hdr
        }
        return primaries == nil ? .unknown : .sdr
    }

    static func fourCCString(_ code: FourCharCode) -> String {
        let bytes = [UInt8(code >> 24 & 0xFF), UInt8(code >> 16 & 0xFF), UInt8(code >> 8 & 0xFF), UInt8(code & 0xFF)]
        return String(bytes: bytes, encoding: .macOSRoman) ?? "????"
    }
}

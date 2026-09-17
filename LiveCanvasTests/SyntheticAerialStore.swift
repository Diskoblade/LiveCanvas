import Foundation
import AVFoundation
@testable import LiveCanvas

/// Builds a throwaway copy of the macOS 26 Aerial store layout so install/restore can be
/// tested end-to-end without ever touching the real one.
struct SyntheticAerialStore {
    let root: URL
    let locator: AerialStoreLocator
    let displayID = "11111111-2222-3333-4444-555555555555"

    static let appleAssetID = "AAAAAAAA-1111-4111-8111-AAAAAAAAAAAA"
    static let secondAppleAssetID = "BBBBBBBB-2222-4222-8222-BBBBBBBBBBBB"
    static let mediaKey = "url-4K-SDR-240FPS"

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("lc-store-\(UUID().uuidString)", isDirectory: true)
        locator = AerialStoreLocator(root: root)
        try build()
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func build() throws {
        let fm = FileManager.default
        for dir in [locator.manifestDirectory, locator.videosDirectory, locator.thumbnailsDirectory, locator.storeDirectory] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try Data(entriesJSON.utf8).write(to: locator.entriesFile)
        try Data("/itunes-assets/Aerials126/v4/test/resources-26-4-1.tar".utf8).write(to: locator.manifestSourceFile)
        try makeManifestTar()
        // Stand-ins for Apple's downloaded videos.
        try Data(repeating: 0xAB, count: 4096).write(to: locator.videoURL(for: Self.appleAssetID))
        try writeIndexPlist(assetID: Self.appleAssetID)
    }

    var entriesJSON: String {
        """
        {"version":1,"localizationVersion":"22L-1","initialAssetCount":2,
         "categories":[{"id":"C-1","localizedNameKey":"AerialCategoryLandscapes",
                        "subcategories":[{"id":"S-1","localizedNameKey":"AerialSubcategoryTahoe"}]}],
         "assets":[
          {"id":"\(Self.appleAssetID)","accessibilityLabel":"Tahoe Day","localizedNameKey":"TA_L_002_NAME",
           "shotID":"TA_L_002","categories":["C-1"],"subcategories":["S-1"],"preferredOrder":1,
           "showInTopLevel":true,"includeInShuffle":true,"pointsOfInterest":{},
           "previewImage":"https://sylvan.apple.invalid/a@2x.png",
           "\(Self.mediaKey)":"https://sylvan.apple.invalid/a.mov"},
          {"id":"\(Self.secondAppleAssetID)","accessibilityLabel":"Sequoia Sunrise","localizedNameKey":"A007_NAME",
           "shotID":"A007_C0001","categories":["C-1"],"subcategories":["S-1"],"preferredOrder":2,
           "showInTopLevel":true,"includeInShuffle":true,"pointsOfInterest":{},
           "previewImage":"https://sylvan.apple.invalid/b@2x.png",
           "\(Self.mediaKey)":"https://sylvan.apple.invalid/b.mov"}
         ]}
        """
    }

    /// Apple's pristine manifest.tar, used by the validator to spot third-party entries.
    private func makeManifestTar() throws {
        let staging = root.appendingPathComponent("tar-staging", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data(entriesJSON.utf8).write(to: staging.appendingPathComponent("entries.json"))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        p.arguments = ["-cf", locator.manifestTar.path, "-C", staging.path, "entries.json"]
        try p.run(); p.waitUntilExit()
        try FileManager.default.removeItem(at: staging)
    }

    /// A Store/Index.plist shaped like the real one, with one display on an Aerial Idle choice.
    func writeIndexPlist(assetID: String) throws {
        let configuration = try AerialIndexStore.configuration(forAssetID: assetID)
        let idle: [String: Any] = [
            "Content": [
                "Choices": [[
                    "Provider": AerialIndexStore.aerialProvider,
                    "Configuration": configuration,
                    "Files": [String]()
                ]],
                "EncodedOptionValues": Data(),
                "Shuffle": "$null"
            ],
            "LastSet": Date(timeIntervalSince1970: 1_700_000_000),
            "LastUse": Date(timeIntervalSince1970: 1_700_000_000)
        ]
        let desktop: [String: Any] = [
            "Content": [
                "Choices": [[
                    "Provider": "com.apple.wallpaper.choice.image",
                    "Configuration": try PropertyListSerialization.data(
                        fromPropertyList: ["type": "imageFile", "url": ["relative": "file:///tmp/x.jpg"]],
                        format: .binary, options: 0),
                    "Files": [String]()
                ]],
                "EncodedOptionValues": Data(),
                "Shuffle": "$null"
            ],
            "LastSet": Date(timeIntervalSince1970: 1_700_000_000),
            "LastUse": Date(timeIntervalSince1970: 1_700_000_000)
        ]
        let plist: [String: Any] = [
            "AllSpacesAndDisplays": "$null",
            "SystemDefault": ["Type": "individual", "Desktop": desktop, "Idle": idle],
            "Spaces": ["SPACE-1": ["Type": "individual", "Desktop": desktop]],
            "Displays": [displayID: ["Type": "individual", "Desktop": desktop, "Idle": idle]]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        try data.write(to: locator.indexFile)
    }

    /// Rewrites Index.plist so no Idle node uses the Aerial provider.
    func writeIndexPlistWithoutAerial() throws {
        var plist = try AerialIndexStore(indexFile: locator.indexFile).readPlist()
        var displays = plist["Displays"] as! [String: Any]
        var display = displays[displayID] as! [String: Any]
        var idle = display["Idle"] as! [String: Any]
        var content = idle["Content"] as! [String: Any]
        var choices = content["Choices"] as! [[String: Any]]
        choices[0]["Provider"] = "com.apple.wallpaper.choice.image"
        content["Choices"] = choices; idle["Content"] = content
        display["Idle"] = idle; displays[displayID] = display; plist["Displays"] = displays
        var systemDefault = plist["SystemDefault"] as! [String: Any]
        var sdIdle = systemDefault["Idle"] as! [String: Any]
        var sdContent = sdIdle["Content"] as! [String: Any]
        var sdChoices = sdContent["Choices"] as! [[String: Any]]
        sdChoices[0]["Provider"] = "com.apple.wallpaper.choice.image"
        sdContent["Choices"] = sdChoices; sdIdle["Content"] = sdContent
        systemDefault["Idle"] = sdIdle; plist["SystemDefault"] = systemDefault
        try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            .write(to: locator.indexFile)
    }

    /// A real, tiny, playable H.264 file to feed the installer.
    static func makeVideo(width: Int = 320, height: Int = 180, frames: Int = 12, withAudio: Bool = false) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lc-src-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        writer.add(input)

        var audioInput: AVAssetWriterInput?
        if withAudio {
            let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1])
            ai.expectsMediaDataInRealTime = false
            writer.add(ai)
            audioInput = ai
        }

        guard writer.startWriting() else { throw writer.error! }
        writer.startSession(atSourceTime: .zero)
        for i in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
            let buffer = pb!
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer)!, Int32(30 + i * 8), CVPixelBufferGetBytesPerRow(buffer) * height)
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 24))
        }
        input.markAsFinished()

        if let ai = audioInput {
            var asbd = AudioStreamBasicDescription(
                mSampleRate: 44100, mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
                mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
            var format: CMAudioFormatDescription?
            CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil,
                                           magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                           formatDescriptionOut: &format)
            let total = 44100 / 2
            var samples = (0..<total).map { Float(sin(Double($0) / 44100 * 440 * 2 * .pi) * 0.2) }
            var block: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: total * 4,
                                               blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
                                               dataLength: total * 4, flags: 0, blockBufferOut: &block)
            samples.withUnsafeMutableBytes {
                CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block!,
                                              offsetIntoDestination: 0, dataLength: total * 4)
            }
            var sample: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: nil, dataBuffer: block!, formatDescription: format!, sampleCount: total,
                presentationTimeStamp: .zero, packetDescriptions: nil, sampleBufferOut: &sample)
            while !ai.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            ai.append(sample!)
            ai.markAsFinished()
        }

        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error! }
        return url
    }
}

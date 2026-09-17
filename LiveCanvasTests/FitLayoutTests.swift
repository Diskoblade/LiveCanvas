import Testing
import CoreGraphics
@testable import LiveCanvas

struct FitLayoutTests {
    let screen16x9 = CGRect(x: 0, y: 0, width: 2560, height: 1440)     // 5K @2x in points
    let screen16x10 = CGRect(x: 0, y: 0, width: 1512, height: 982)     // MacBook Pro 14" points
    let ultrawide = CGRect(x: 0, y: 0, width: 3440, height: 1440)
    let portraitScreen = CGRect(x: 0, y: 0, width: 1080, height: 1920)

    @Test func fillFitStretchUseFullBounds() {
        for mode in [FitMode.fill, .fit, .stretch] {
            let r = FitLayout.layout(mode: mode, bounds: screen16x10, videoPixelSize: CGSize(width: 3840, height: 2160), scale: 2)
            #expect(r.frame == screen16x10)
        }
        #expect(FitLayout.layout(mode: .fill, bounds: screen16x9, videoPixelSize: .zero, scale: 2).gravity == .resizeAspectFill)
        #expect(FitLayout.layout(mode: .fit, bounds: screen16x9, videoPixelSize: .zero, scale: 2).gravity == .resizeAspect)
        #expect(FitLayout.layout(mode: .stretch, bounds: screen16x9, videoPixelSize: .zero, scale: 2).gravity == .resize)
    }

    @Test func originalCentresAtOneToOneDevicePixels() {
        let r = FitLayout.layout(mode: .original, bounds: screen16x9, videoPixelSize: CGSize(width: 1920, height: 1080), scale: 2)
        #expect(r.gravity == .resize)
        #expect(r.frame == CGRect(x: 800, y: 450, width: 960, height: 540))
    }

    @Test func originalFallsBackToFitWhenLargerThanScreen() {
        let r = FitLayout.layout(mode: .original, bounds: screen16x10, videoPixelSize: CGSize(width: 7680, height: 4320), scale: 2)
        #expect(r.gravity == .resizeAspect)
        #expect(r.frame == screen16x10)
    }

    @Test func fitLetterboxesUltrawideOn16x9() {
        let r = FitLayout.layout(mode: .fit, bounds: screen16x9, videoPixelSize: CGSize(width: 3440, height: 1440), scale: 2)
        let c = FitLayout.contentRect(for: r, videoPixelSize: CGSize(width: 3440, height: 1440))
        #expect(c.width == 2560)
        #expect(abs(c.height - 2560 * 1440 / 3440) < 0.5)
        #expect(c.minY > 0)                                   // letterboxed
    }

    @Test func fillCropsPortraitOnLandscape() {
        let r = FitLayout.layout(mode: .fill, bounds: screen16x9, videoPixelSize: CGSize(width: 1080, height: 1920), scale: 2)
        let c = FitLayout.contentRect(for: r, videoPixelSize: CGSize(width: 1080, height: 1920))
        #expect(c.width == 2560)
        #expect(c.height > screen16x9.height)                  // overflow is cropped
        #expect(abs(c.midX - screen16x9.midX) < 0.5)
    }

    @Test func portraitScreenPillarboxesLandscapeVideoInFit() {
        let r = FitLayout.layout(mode: .fit, bounds: portraitScreen, videoPixelSize: CGSize(width: 3840, height: 2160), scale: 1)
        let c = FitLayout.contentRect(for: r, videoPixelSize: CGSize(width: 3840, height: 2160))
        #expect(c.width == 1080)
        #expect(c.height < portraitScreen.height)
    }

    @Test func scaleOneUsesPixelsAsPoints() {
        let r = FitLayout.layout(mode: .original, bounds: ultrawide, videoPixelSize: CGSize(width: 1280, height: 720), scale: 1)
        #expect(r.frame.size == CGSize(width: 1280, height: 720))
        #expect(r.frame.origin == CGPoint(x: 1080, y: 360))
    }
}

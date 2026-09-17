import Testing
import AppKit
@testable import LiveCanvas

/// These run against the real displays of the machine executing the tests.
@MainActor
struct DisplayIdentityTests {
    @Test func everyScreenProducesAStableNonEmptyIdentifier() {
        let screens = NSScreen.screens
        #expect(!screens.isEmpty)
        let ids = screens.map { DisplayManager.identifier(for: $0) }
        #expect(ids.allSatisfy { !$0.isEmpty })
        #expect(Set(ids).count == ids.count)                       // unique per display
        #expect(ids == screens.map { DisplayManager.identifier(for: $0) })   // stable across calls
    }

    @Test func configurationMatchesScreenGeometry() {
        for screen in NSScreen.screens {
            let c = DisplayManager.configuration(for: screen)
            #expect(c.frame == screen.frame)
            #expect(c.backingScaleFactor == screen.backingScaleFactor)
            #expect(c.pixelSize.width == screen.frame.width * screen.backingScaleFactor)
            #expect(c.aspectRatio > 0)
            #expect(!c.name.isEmpty)
        }
    }

    @Test func managerReportsAllScreens() {
        let manager = DisplayManager()
        #expect(manager.displays.count == NSScreen.screens.count)
        #expect(manager.displays.filter(\.isMain).count <= 1)
        for d in manager.displays {
            #expect(manager.screen(for: d) != nil)
        }
    }
}

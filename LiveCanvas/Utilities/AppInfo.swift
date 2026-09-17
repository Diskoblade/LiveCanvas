import Foundation
import ObjectiveC

/// Single source of truth for product identity. The name comes from the bundle so
/// renaming the product only requires editing `Config/Shared.xcconfig`.
enum AppInfo {
    static var name: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "LiveCanvas"
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.rahul.livecanvas"
    }

    static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    }

    /// True when the process was launched by the test runner rather than by a user.
    /// The app is its own test host, so without this the wallpaper engine would put real
    /// windows on the tester's desktop and fight with the unit tests for AV resources.
    static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
    }

    static var build: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0"
    }
}

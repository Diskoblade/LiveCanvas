import OSLog

/// Central OSLog loggers. Never log file contents; paths are fine.
enum Log {
    private static let subsystem = AppInfo.bundleIdentifier

    static let app = Logger(subsystem: subsystem, category: "app")
    static let playback = Logger(subsystem: subsystem, category: "playback")
    static let displays = Logger(subsystem: subsystem, category: "displays")
    static let media = Logger(subsystem: subsystem, category: "media")
    static let lockscreen = Logger(subsystem: subsystem, category: "lockscreen")
    static let power = Logger(subsystem: subsystem, category: "power")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
}

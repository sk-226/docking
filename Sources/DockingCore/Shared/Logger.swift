import OSLog

enum DockingLog {
    // Keep the subsystem aligned with the bundle identifier but free of local
    // user names. This string appears in logs and can be copied into QA output,
    // so it should identify the product rather than the developer's machine.
    static let subsystem = "app.docking.docking"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let dock = Logger(subsystem: subsystem, category: "dock")
    static let calendar = Logger(subsystem: subsystem, category: "calendar")
    static let weather = Logger(subsystem: subsystem, category: "weather")
    static let restore = Logger(subsystem: subsystem, category: "restore")
}

import OSLog

enum DockingLog {
    static let subsystem = "com.sugu.docking"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let dock = Logger(subsystem: subsystem, category: "dock")
    static let calendar = Logger(subsystem: subsystem, category: "calendar")
    static let weather = Logger(subsystem: subsystem, category: "weather")
    static let restore = Logger(subsystem: subsystem, category: "restore")
}

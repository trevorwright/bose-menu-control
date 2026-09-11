import OSLog

enum Log {
    static let bluetooth = Logger(subsystem: "local.bose.menucontrol", category: "bluetooth")
    static let controller = Logger(subsystem: "local.bose.menucontrol", category: "controller")
}

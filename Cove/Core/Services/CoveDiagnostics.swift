import OSLog

enum CoveLog {
    private static let subsystem = "com.ankitbhade.Cove"

    static let vault = Logger(subsystem: subsystem, category: "Vault")
    static let document = Logger(subsystem: subsystem, category: "Document")
    static let widget = Logger(subsystem: subsystem, category: "Widget")
    static let notifications = Logger(subsystem: subsystem, category: "Notifications")
    static let index = Logger(subsystem: subsystem, category: "Index")
}

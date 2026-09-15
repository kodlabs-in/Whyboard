import OSLog

enum AppLog {
  static let persistence = Logger(
    subsystem: "in.kodlabs.whyboard",
    category: "persistence")
  static let editor = Logger(
    subsystem: "in.kodlabs.whyboard",
    category: "editor")
}

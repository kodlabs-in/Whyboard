import Foundation
import OSLog

nonisolated struct AppSignpostInterval: @unchecked Sendable {
  private let name: StaticString
  private let identifier: OSSignpostID

  init(_ name: StaticString) {
    self.name = name
    identifier = OSSignpostID(log: AppSignpost.log)
    os_signpost(.begin, log: AppSignpost.log, name: name, signpostID: identifier)
  }

  func end() {
    os_signpost(.end, log: AppSignpost.log, name: name, signpostID: identifier)
  }
}

nonisolated enum AppSignpost {
  static let log = OSLog(
    subsystem: "in.kodlabs.whyboard",
    category: .pointsOfInterest)

  static func interval(_ name: StaticString) -> AppSignpostInterval {
    AppSignpostInterval(name)
  }

  static func event(_ name: StaticString) {
    os_signpost(.event, log: log, name: name)
  }
}

nonisolated enum ThermalPolicy {
  static var allowsSpeculativeWork: Bool {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal, .fair:
      true
    case .serious, .critical:
      false
    @unknown default:
      false
    }
  }
}

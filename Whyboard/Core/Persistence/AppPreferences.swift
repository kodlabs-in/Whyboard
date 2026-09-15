import Foundation

enum AppPreferences {
  static let store: UserDefaults = {
    guard ProcessInfo.processInfo.isRunningTests else { return .standard }

    let suiteName = "in.kodlabs.whyboard.tests"
    let store = UserDefaults(suiteName: suiteName) ?? .standard
    store.removePersistentDomain(forName: suiteName)
    return store
  }()
}

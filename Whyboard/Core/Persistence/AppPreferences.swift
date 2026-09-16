import Foundation

enum AppPreferences {
  static let store: UserDefaults = {
    #if DEBUG
      if ProcessInfo.processInfo.isRunningAutomatedTest {
        let suiteName = "in.kodlabs.whyboard.tests"
        let store = UserDefaults(suiteName: suiteName) ?? .standard
        store.removePersistentDomain(forName: suiteName)
        return store
      }
    #endif
    return .standard
  }()
}

import Foundation

enum AppPreferences {
  static let store: UserDefaults = {
    #if DEBUG
      if ProcessInfo.processInfo.isRunningAutomatedTest {
        let suiteName = "in.kodlabs.whyboard.tests"
        let store = UserDefaults(suiteName: suiteName) ?? .standard
        store.removePersistentDomain(forName: suiteName)
        if ProcessInfo.processInfo.environment["WHYBOARD_UI_TEST_DRAW_WITH_FINGER"] == "1" {
          store.set(true, forKey: "drawWithFinger")
        }
        return store
      }
    #endif
    return .standard
  }()
}

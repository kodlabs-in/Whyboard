import SwiftData
import SwiftUI

@main
struct WhyboardApp: App {
  private let bootstrap: AppBootstrap

  init() {
    do {
      bootstrap = .ready(try AppEnvironment.make())
    } catch {
      bootstrap = .failed(error.localizedDescription)
    }
  }

  var body: some Scene {
    WindowGroup {
      switch bootstrap {
      case .ready(let environment):
        LibraryView(drawingRepository: environment.drawingRepository)
          .modelContainer(environment.modelContainer)
      case .failed(let message):
        ContentUnavailableView(
          "Whyboard couldn't open",
          systemImage: "exclamationmark.triangle",
          description: Text(message))
      }
    }
  }
}

private enum AppBootstrap {
  case ready(AppEnvironment)
  case failed(String)
}

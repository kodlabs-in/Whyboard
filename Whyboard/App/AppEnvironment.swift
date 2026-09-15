import Foundation
import SwiftData

struct AppEnvironment {
  let modelContainer: ModelContainer
  let drawingRepository: DrawingRepository

  static func make() throws -> AppEnvironment {
    let isTesting = ProcessInfo.processInfo.isRunningTests
    let directories = try AppDirectories.make(isTesting: isTesting)
    let schema = Schema([
      Folder.self,
      Note.self,
      Page.self,
    ])
    let configuration = modelConfiguration(
      schema: schema,
      directories: directories,
      isTesting: isTesting)
    let container = try ModelContainer(
      for: schema,
      configurations: [configuration])
    try LibrarySeeder.seedIfNeeded(in: container.mainContext)

    return AppEnvironment(
      modelContainer: container,
      drawingRepository: DrawingRepository(directories: directories))
  }

  private static func modelConfiguration(
    schema: Schema,
    directories: AppDirectories,
    isTesting: Bool
  ) -> ModelConfiguration {
    if isTesting {
      return ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    }

    return ModelConfiguration(
      "Whyboard",
      schema: schema,
      url: directories.metadata.appending(path: "Whyboard.store"),
      cloudKitDatabase: .none)
  }
}

extension ProcessInfo {
  var isRunningTests: Bool {
    arguments.contains("-ui-testing")
      || environment["XCTestConfigurationFilePath"] != nil
  }
}

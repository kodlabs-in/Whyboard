import Foundation
import SwiftData

struct AppEnvironment {
  let modelContainer: ModelContainer
  let drawingRepository: DrawingRepository

  static func make() throws -> AppEnvironment {
    let schema = Schema([
      Folder.self,
      Note.self,
      Page.self,
      ImportedDocument.self,
    ])

    let directories: AppDirectories
    let configuration: ModelConfiguration
    #if DEBUG
      if ProcessInfo.processInfo.isRunningAutomatedTest {
        let root = FileManager.default.temporaryDirectory
          .appending(path: "WhyboardTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        directories = try AppDirectories.make(root: root)
        configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
      } else {
        directories = try AppDirectories.make()
        configuration = persistentModelConfiguration(schema: schema, directories: directories)
      }
    #else
      directories = try AppDirectories.make()
      configuration = persistentModelConfiguration(schema: schema, directories: directories)
    #endif

    let container = try ModelContainer(
      for: schema,
      configurations: [configuration])
    try LibrarySeeder.seedIfNeeded(in: container.mainContext)

    return AppEnvironment(
      modelContainer: container,
      drawingRepository: DrawingRepository(directories: directories))
  }

  private static func persistentModelConfiguration(
    schema: Schema,
    directories: AppDirectories
  ) -> ModelConfiguration {
    ModelConfiguration(
      "Whyboard",
      schema: schema,
      url: directories.metadata.appending(path: "Whyboard.store"),
      cloudKitDatabase: .none)
  }
}

#if DEBUG
  extension ProcessInfo {
    var isRunningAutomatedTest: Bool {
      arguments.contains("-ui-testing")
        || environment["XCTestConfigurationFilePath"] != nil
    }
  }
#endif

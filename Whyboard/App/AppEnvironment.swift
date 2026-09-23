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
      if let testStorage = ProcessInfo.processInfo.persistentUITestStorage {
        let shouldResetStorage =
          testStorage.resetsStorage
          && FileManager.default.fileExists(atPath: testStorage.root.path)
        if shouldResetStorage {
          try FileManager.default.removeItem(at: testStorage.root)
        }
        directories = try AppDirectories.make(root: testStorage.root)
        configuration = persistentModelConfiguration(schema: schema, directories: directories)
      } else if ProcessInfo.processInfo.isRunningAutomatedTest {
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
  struct PersistentUITestStorage: Equatable {
    let root: URL
    let resetsStorage: Bool
  }

  extension ProcessInfo {
    var isRunningAutomatedTest: Bool {
      arguments.contains("-ui-testing")
        || environment["XCTestConfigurationFilePath"] != nil
    }

    var persistentUITestStorage: PersistentUITestStorage? {
      guard arguments.contains("-ui-testing-persistent") else { return nil }
      guard let identifier = environment["WHYBOARD_UI_TEST_ID"] else { return nil }
      let permitted = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
      guard
        !identifier.isEmpty,
        identifier.count <= 100,
        identifier.unicodeScalars.allSatisfy(permitted.contains)
      else { return nil }
      return PersistentUITestStorage(
        root: FileManager.default.temporaryDirectory.appending(
          path: "WhyboardUITests-\(identifier)",
          directoryHint: .isDirectory),
        resetsStorage: arguments.contains("-ui-testing-reset"))
    }
  }
#endif

import Foundation

@testable import Whyboard

extension AppDirectories {
  static func makeForTesting() throws -> AppDirectories {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "WhyboardTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    return try make(root: root)
  }
}

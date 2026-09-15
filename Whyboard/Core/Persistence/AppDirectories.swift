import Foundation

struct AppDirectories: Sendable {
  let root: URL
  let metadata: URL
  let drawings: URL
  let previews: URL
  let recovery: URL

  static func make(isTesting: Bool) throws -> AppDirectories {
    let root = try rootURL(isTesting: isTesting)
    let directories = AppDirectories(
      root: root,
      metadata: root.appending(path: "Metadata", directoryHint: .isDirectory),
      drawings: root.appending(path: "Drawings", directoryHint: .isDirectory),
      previews: root.appending(path: "Previews", directoryHint: .isDirectory),
      recovery: root.appending(path: "Recovery", directoryHint: .isDirectory))
    try directories.createIfNeeded()
    return directories
  }

  private static func rootURL(isTesting: Bool) throws -> URL {
    if isTesting {
      return FileManager.default.temporaryDirectory
        .appending(path: "WhyboardTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    return try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    .appending(path: "Whyboard", directoryHint: .isDirectory)
  }

  private func createIfNeeded() throws {
    for directory in [root, metadata, drawings, previews, recovery] {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true)
    }
  }
}

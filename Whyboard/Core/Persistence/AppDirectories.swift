import Foundation

struct AppDirectories: Sendable {
  let root: URL
  let metadata: URL
  let drawings: URL
  let previews: URL
  let attachments: URL
  let documents: URL
  let exports: URL
  let backups: URL
  let recovery: URL

  static func make(root customRoot: URL? = nil) throws -> AppDirectories {
    let root: URL
    if let customRoot {
      root = customRoot
    } else {
      root = try applicationSupportRootURL()
    }
    let directories = AppDirectories(
      root: root,
      metadata: root.appending(path: "Metadata", directoryHint: .isDirectory),
      drawings: root.appending(path: "Drawings", directoryHint: .isDirectory),
      previews: root.appending(path: "Previews", directoryHint: .isDirectory),
      attachments: root.appending(path: "Attachments", directoryHint: .isDirectory),
      documents: root.appending(path: "Documents", directoryHint: .isDirectory),
      exports: root.appending(path: "Exports", directoryHint: .isDirectory),
      backups: root.appending(path: "Backups", directoryHint: .isDirectory),
      recovery: root.appending(path: "Recovery", directoryHint: .isDirectory))
    try directories.createIfNeeded()
    return directories
  }

  private static func applicationSupportRootURL() throws -> URL {
    try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    .appending(path: "Whyboard", directoryHint: .isDirectory)
  }

  private func createIfNeeded() throws {
    for directory in [
      root, metadata, drawings, previews, attachments, documents, exports, backups, recovery,
    ] {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true)
    }
  }
}

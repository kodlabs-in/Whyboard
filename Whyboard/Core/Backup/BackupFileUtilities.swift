import CryptoKit
import Foundation

enum BackupFileError: LocalizedError {
  case unsafePath
  case checksumMismatch
  case missingPayload
  case copyFailed
  case insufficientStorage

  var errorDescription: String? {
    switch self {
    case .unsafePath:
      "The backup contains an unsafe file path."
    case .checksumMismatch:
      "The backup failed its integrity check."
    case .missingPayload:
      "The backup is missing a required file."
    case .copyFailed:
      "Whyboard couldn't copy a backup file."
    case .insufficientStorage:
      "There isn't enough free storage to complete this operation safely."
    }
  }
}

nonisolated struct BackupSourceFile: Sendable {
  let url: URL
  let relativePath: String
}

nonisolated enum BackupFileUtilities {
  private static let legacyAliasComponents = [
    "drawings": "rawings",
    "attachments": "chments",
    "documents": "cuments",
  ]

  static func sourceFiles(
    noteIDs: Set<UUID>,
    drawingRepository: DrawingRepository
  ) -> [BackupSourceFile] {
    let roots = [
      ("drawings", drawingRepository.drawingsDirectory),
      ("attachments", drawingRepository.attachments.rootDirectory),
      ("documents", drawingRepository.documents.rootDirectory),
    ]
    return roots.flatMap { category, root in
      noteIDs.flatMap { noteID in
        files(
          below: root.appending(path: noteID.uuidString.lowercased()),
          root: root,
          category: category)
      }
    }
    .sorted { $0.relativePath < $1.relativePath }
  }

  static func sha256(of url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
      hasher.update(data: data)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  static func isSafeRelativePath(_ path: String) -> Bool {
    guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    return !components.contains { $0.isEmpty || $0 == "." || $0 == ".." }
  }

  static func canonicalPayloadRelativePath(_ path: String) -> String {
    var components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard
      components.count > 2,
      legacyAliasComponents[components[0]] == components[1]
    else { return path }
    components.remove(at: 1)
    return components.joined(separator: "/")
  }

  static func relativePath(of file: URL, under root: URL) -> String? {
    let fileComponents = normalizedPathComponents(of: file)
    let rootComponents = normalizedPathComponents(of: root)
    guard
      fileComponents.count > rootComponents.count,
      fileComponents.starts(with: rootComponents)
    else { return nil }
    return fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
  }

  private static func normalizedPathComponents(of url: URL) -> [String] {
    var components = url.standardizedFileURL.pathComponents
    let usesPrivateVarAlias =
      components.count > 2 && components[0] == "/"
      && components[1] == "private" && components[2] == "var"
    if usesPrivateVarAlias {
      components.remove(at: 1)
    }
    return components
  }

  static func copyFile(from source: URL, to destination: URL) throws {
    do {
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true)
      try FileManager.default.copyItem(at: source, to: destination)
    } catch {
      throw BackupFileError.copyFailed
    }
  }

  static func byteSize(of url: URL) throws -> Int64 {
    let values = try url.resourceValues(forKeys: [.fileSizeKey])
    return Int64(values.fileSize ?? 0)
  }

  private static func files(
    below directory: URL,
    root: URL,
    category: String
  ) -> [BackupSourceFile] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles])
    else { return [] }
    return enumerator.compactMap { item in
      guard
        let url = item as? URL,
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
      else { return nil }
      guard let relative = relativePath(of: url, under: root) else { return nil }
      return BackupSourceFile(url: url, relativePath: "\(category)/\(relative)")
    }
  }
}

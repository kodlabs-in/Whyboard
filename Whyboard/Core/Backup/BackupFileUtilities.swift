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

nonisolated struct BackupSourcePreflight: Sendable {
  let totalBytes: Int64
}

nonisolated enum BackupFileUtilities {
  private static let legacyAliasComponents = [
    "drawings": "rawings",
    "attachments": "chments",
    "documents": "cuments",
  ]

  static func sourceFiles(
    library: BackupLibrary,
    referencedAttachmentPaths: Set<String>,
    drawingRepository: DrawingRepository
  ) -> [BackupSourceFile] {
    let drawings = library.pages.compactMap { page -> BackupSourceFile? in
      let noteID = page.noteID.uuidString.lowercased()
      let filename = "\(page.id.uuidString.lowercased()).drawing"
      let url = drawingRepository.drawingsDirectory
        .appending(path: noteID, directoryHint: .isDirectory)
        .appending(path: filename)
      // A page with no on-disk drawing is a supported empty drawing.
      guard FileManager.default.fileExists(atPath: url.path) else { return nil }
      return BackupSourceFile(url: url, relativePath: "drawings/\(noteID)/\(filename)")
    }
    let documents = library.importedDocuments.map { document in
      let noteID = document.noteID.uuidString.lowercased()
      let filename = "\(document.id.uuidString.lowercased()).pdf"
      return BackupSourceFile(
        url: drawingRepository.documents.rootDirectory
          .appending(path: noteID, directoryHint: .isDirectory)
          .appending(path: filename),
        relativePath: "documents/\(noteID)/\(filename)")
    }
    let referencedAttachments = referencedAttachmentPaths.compactMap {
      attachmentSourceFile(
        relativePath: $0,
        attachmentsRoot: drawingRepository.attachments.rootDirectory)
    }
    return (drawings + documents + referencedAttachments).sorted {
      $0.relativePath < $1.relativePath
    }
  }

  static func sha256(of url: URL) throws -> String {
    try Task.checkCancellation()
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
      try Task.checkCancellation()
      hasher.update(data: data)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  static func preflight(_ files: [BackupSourceFile]) throws -> BackupSourcePreflight {
    guard files.count <= ResourceLimits.maximumPayloadFiles else {
      throw BackupValidationError.resourceLimitExceeded
    }
    guard Set(files.map(\.relativePath)).count == files.count else {
      throw BackupValidationError.duplicatePayload
    }
    var totalBytes: Int64 = 0
    for file in files {
      guard isSafeRelativePath(file.relativePath) else { throw BackupFileError.unsafePath }
      let values = try file.url.resourceValues(
        forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
      guard
        values.isRegularFile == true,
        values.isSymbolicLink != true,
        let fileSize = values.fileSize,
        fileSize >= 0
      else { throw BackupValidationError.unexpectedFile }
      let byteSize = Int64(fileSize)
      guard byteSize <= maximumPayloadBytes(for: file.relativePath) else {
        throw BackupValidationError.resourceLimitExceeded
      }
      let (nextTotal, overflow) = totalBytes.addingReportingOverflow(byteSize)
      guard !overflow, nextTotal <= ResourceLimits.maximumTotalPayloadBytes else {
        throw BackupValidationError.resourceLimitExceeded
      }
      totalBytes = nextTotal
    }
    return BackupSourcePreflight(totalBytes: totalBytes)
  }

  static func maximumPayloadBytes(for relativePath: String) -> Int64 {
    switch canonicalPayloadRelativePath(relativePath).split(separator: "/").first {
    case "attachments":
      ResourceLimits.maximumImageSourceBytes
    case "documents":
      ResourceLimits.maximumPDFSourceBytes
    default:
      ResourceLimits.maximumPayloadBytes
    }
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

  private static func attachmentSourceFile(
    relativePath: String,
    attachmentsRoot: URL
  ) -> BackupSourceFile? {
    let prefix = "attachments/"
    guard
      relativePath.hasPrefix(prefix),
      isSafeRelativePath(relativePath)
    else { return nil }
    let pathBelowRoot = String(relativePath.dropFirst(prefix.count))
    return BackupSourceFile(
      url: attachmentsRoot.appending(path: pathBelowRoot),
      relativePath: relativePath)
  }

  static func copyFile(from source: URL, to destination: URL) throws {
    do {
      try Task.checkCancellation()
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true)
      guard
        FileManager.default.createFile(
          atPath: destination.path,
          contents: nil,
          attributes: [.protectionKey: FileProtectionType.complete])
      else { throw BackupFileError.copyFailed }
      let input = try FileHandle(forReadingFrom: source)
      defer { try? input.close() }
      let output = try FileHandle(forWritingTo: destination)
      defer { try? output.close() }
      while let data = try input.read(upToCount: 1_048_576), !data.isEmpty {
        try Task.checkCancellation()
        try output.write(contentsOf: data)
      }
      try output.synchronize()
    } catch is CancellationError {
      try? FileManager.default.removeItem(at: destination)
      throw CancellationError()
    } catch {
      try? FileManager.default.removeItem(at: destination)
      throw BackupFileError.copyFailed
    }
  }

  static func byteSize(of url: URL) throws -> Int64 {
    let values = try url.resourceValues(forKeys: [.fileSizeKey])
    return Int64(values.fileSize ?? 0)
  }

}

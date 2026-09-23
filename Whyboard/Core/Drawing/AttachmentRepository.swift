import Foundation
import ImageIO
import UniformTypeIdentifiers

enum AttachmentStorageError: LocalizedError, Sendable {
  case importFailed
  case unsupportedFile
  case resourceLimitExceeded

  var errorDescription: String? {
    switch self {
    case .importFailed:
      "Whyboard could not copy this attachment into the note."
    case .unsupportedFile:
      "This file type is not supported. Choose an image file."
    case .resourceLimitExceeded:
      "This image is too large to import safely."
    }
  }
}

struct StoredImageAttachment: Sendable {
  let filename: String
  let aspectRatio: Double
}

actor AttachmentRepository {
  nonisolated let rootDirectory: URL

  private let fileManager: FileManager

  init(directories: AppDirectories) {
    rootDirectory = directories.attachments
    fileManager = .default
  }

  func importFile(
    at source: URL,
    noteID: UUID,
    pageID: UUID
  ) throws -> String {
    let didAccess = source.startAccessingSecurityScopedResource()
    defer {
      if didAccess {
        source.stopAccessingSecurityScopedResource()
      }
    }

    let fileExtension = source.pathExtension.isEmpty ? "data" : source.pathExtension.lowercased()
    let filename = "\(UUID().uuidString.lowercased()).\(fileExtension)"
    let directory = pageDirectory(noteID: noteID, pageID: pageID)
    let destination = directory.appending(path: filename)

    do {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
      try fileManager.copyItem(at: source, to: destination)
      return filename
    } catch {
      try? fileManager.removeItem(at: destination)
      throw AttachmentStorageError.importFailed
    }
  }

  func importImage(
    at source: URL,
    noteID: UUID,
    pageID: UUID
  ) throws -> StoredImageAttachment {
    let didAccess = source.startAccessingSecurityScopedResource()
    defer {
      if didAccess {
        source.stopAccessingSecurityScopedResource()
      }
    }

    do {
      let byteSize = try ImportFilePreflight.inspectRegularFile(
        source,
        maximumBytes: ResourceLimits.maximumImageSourceBytes)
      try ImportFilePreflight.requireCapacity(for: byteSize, at: rootDirectory)
    } catch ImportFilePreflightError.invalidSource {
      throw AttachmentStorageError.unsupportedFile
    } catch let error as ImportFilePreflightError {
      switch error {
      case .resourceLimitExceeded, .insufficientStorage:
        throw AttachmentStorageError.resourceLimitExceeded
      case .invalidSource:
        throw AttachmentStorageError.unsupportedFile
      }
    } catch {
      throw AttachmentStorageError.importFailed
    }

    let fileExtension = source.pathExtension.isEmpty ? "data" : source.pathExtension.lowercased()
    let filename = "\(UUID().uuidString.lowercased()).\(fileExtension)"
    let directory = pageDirectory(noteID: noteID, pageID: pageID)
    let destination = directory.appending(path: filename)
    do {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
      try fileManager.copyItem(at: source, to: destination)
    } catch {
      try? fileManager.removeItem(at: destination)
      throw AttachmentStorageError.importFailed
    }

    do {
      let metadata = try ImageResourceValidator.validate(destination)
      return StoredImageAttachment(filename: filename, aspectRatio: metadata.aspectRatio)
    } catch {
      try? fileManager.removeItem(at: destination)
      throw error
    }
  }

  nonisolated func fileURL(noteID: UUID, pageID: UUID, filename: String) -> URL {
    pageDirectory(noteID: noteID, pageID: pageID).appending(path: filename)
  }

  func copyFiles(
    _ filenames: Set<String>,
    fromNoteID: UUID,
    fromPageID: UUID,
    toNoteID: UUID,
    toPageID: UUID
  ) throws {
    guard !filenames.isEmpty else { return }
    guard filenames.allSatisfy(isSafeFilename) else {
      throw AttachmentStorageError.importFailed
    }

    let destination = pageDirectory(noteID: toNoteID, pageID: toPageID)
    do {
      try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
      for filename in filenames {
        try copyFile(
          filename,
          fromNoteID: fromNoteID,
          fromPageID: fromPageID,
          to: destination)
      }
    } catch {
      throw AttachmentStorageError.importFailed
    }
  }

  func delete(filename: String, noteID: UUID, pageID: UUID) {
    try? fileManager.removeItem(
      at: fileURL(noteID: noteID, pageID: pageID, filename: filename))
  }

  func removeUnreferencedFiles(
    noteID: UUID,
    pageID: UUID,
    keeping referencedFilenames: Set<String>
  ) {
    let directory = pageDirectory(noteID: noteID, pageID: pageID)
    guard
      let fileURLs = try? fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles])
    else { return }

    for fileURL in fileURLs where !referencedFilenames.contains(fileURL.lastPathComponent) {
      guard
        let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
        values.isRegularFile == true
      else { continue }
      try? fileManager.removeItem(at: fileURL)
    }
  }

  func deletePage(pageID: UUID, noteID: UUID) {
    try? fileManager.removeItem(at: pageDirectory(noteID: noteID, pageID: pageID))
  }

  func deleteNote(noteID: UUID) {
    try? fileManager.removeItem(at: noteDirectory(noteID: noteID))
  }

  private nonisolated func pageDirectory(noteID: UUID, pageID: UUID) -> URL {
    noteDirectory(noteID: noteID)
      .appending(path: pageID.uuidString.lowercased(), directoryHint: .isDirectory)
  }

  private nonisolated func noteDirectory(noteID: UUID) -> URL {
    rootDirectory
      .appending(path: noteID.uuidString.lowercased(), directoryHint: .isDirectory)
  }

  private func copyFile(
    _ filename: String,
    fromNoteID: UUID,
    fromPageID: UUID,
    to destination: URL
  ) throws {
    let source = fileURL(noteID: fromNoteID, pageID: fromPageID, filename: filename)
    guard fileManager.fileExists(atPath: source.path) else {
      throw AttachmentStorageError.importFailed
    }
    try fileManager.copyItem(
      at: source,
      to: destination.appending(path: filename))
  }

  private nonisolated func isSafeFilename(_ filename: String) -> Bool {
    let reservedNames: Set<String> = [".", ".."]
    return !filename.isEmpty
      && !reservedNames.contains(filename)
      && URL(fileURLWithPath: filename).lastPathComponent == filename
  }

}

nonisolated enum ImageResourceValidator {
  struct Metadata: Sendable {
    let aspectRatio: Double
  }

  static func validate(_ url: URL) throws -> Metadata {
    do {
      _ = try ImportFilePreflight.inspectRegularFile(
        url,
        maximumBytes: ResourceLimits.maximumImageSourceBytes)
    } catch ImportFilePreflightError.invalidSource {
      throw AttachmentStorageError.unsupportedFile
    } catch {
      throw AttachmentStorageError.resourceLimitExceeded
    }
    try Task.checkCancellation()
    guard
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      CGImageSourceGetCount(source) == 1,
      let typeIdentifier = CGImageSourceGetType(source) as String?,
      let actualType = UTType(typeIdentifier),
      actualType.conforms(to: .image)
    else { throw AttachmentStorageError.unsupportedFile }
    let claimedType = UTType(filenameExtension: url.pathExtension)
    let mismatchesClaimedType =
      claimedType.map {
        $0.conforms(to: .image)
          && actualType != $0
          && !actualType.conforms(to: $0)
          && !$0.conforms(to: actualType)
      } ?? false
    if mismatchesClaimedType {
      throw AttachmentStorageError.unsupportedFile
    }
    try Task.checkCancellation()
    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let widthNumber = properties[kCGImagePropertyPixelWidth] as? NSNumber,
      let heightNumber = properties[kCGImagePropertyPixelHeight] as? NSNumber
    else { throw AttachmentStorageError.unsupportedFile }
    var width = widthNumber.int64Value
    var height = heightNumber.int64Value
    guard width > 0, height > 0 else { throw AttachmentStorageError.unsupportedFile }
    let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    if (5...8).contains(orientation) {
      swap(&width, &height)
    }
    let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
    guard !overflow, pixels <= ResourceLimits.maximumImagePixels else {
      throw AttachmentStorageError.resourceLimitExceeded
    }
    return Metadata(aspectRatio: Double(width) / Double(height))
  }
}

import Foundation

enum AttachmentStorageError: LocalizedError, Sendable {
  case importFailed
  case unsupportedFile

  var errorDescription: String? {
    switch self {
    case .importFailed:
      "Whyboard could not copy this attachment into the note."
    case .unsupportedFile:
      "This file type is not supported. Choose an image file."
    }
  }
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
      throw AttachmentStorageError.importFailed
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

import Foundation
import PencilKit

enum DrawingStorageError: LocalizedError, Sendable {
  case invalidDrawing
  case readFailed
  case writeFailed

  var errorDescription: String? {
    switch self {
    case .invalidDrawing:
      "This page's drawing data is damaged. The existing file was left untouched."
    case .readFailed:
      "Whyboard could not read this page from local storage."
    case .writeFailed:
      "Whyboard could not save this page. Your current drawing remains open."
    }
  }
}

actor DrawingRepository {
  nonisolated let previews: PreviewRepository

  private let directories: AppDirectories
  private let fileManager: FileManager

  init(directories: AppDirectories, fileManager: FileManager = .default) {
    self.directories = directories
    self.fileManager = fileManager
    previews = PreviewRepository(directories: directories)
  }

  func load(pageID: UUID, noteID: UUID) throws -> PKDrawing {
    let url = drawingURL(pageID: pageID, noteID: noteID)
    guard fileManager.fileExists(atPath: url.path) else { return PKDrawing() }

    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      throw DrawingStorageError.readFailed
    }

    do {
      return try PKDrawing(data: data)
    } catch {
      throw DrawingStorageError.invalidDrawing
    }
  }

  func save(_ drawing: PKDrawing, pageID: UUID, noteID: UUID) throws {
    let noteDirectory = noteDrawingDirectory(noteID: noteID)
    try createDirectory(noteDirectory)

    let destination = drawingURL(pageID: pageID, noteID: noteID)
    let temporary = directories.recovery
      .appending(path: "\(UUID().uuidString).drawing")

    do {
      try drawing.dataRepresentation().write(
        to: temporary,
        options: [.atomic, .completeFileProtection])
      try replace(destination: destination, with: temporary)
    } catch {
      try? fileManager.removeItem(at: temporary)
      throw DrawingStorageError.writeFailed
    }
  }

  func deletePage(pageID: UUID, noteID: UUID) async {
    try? fileManager.removeItem(at: drawingURL(pageID: pageID, noteID: noteID))
    await previews.deletePage(pageID: pageID, noteID: noteID)
  }

  func deleteNote(noteID: UUID) async {
    try? fileManager.removeItem(at: noteDrawingDirectory(noteID: noteID))
    await previews.deleteNote(noteID: noteID)
  }

  private func drawingURL(pageID: UUID, noteID: UUID) -> URL {
    noteDrawingDirectory(noteID: noteID)
      .appending(path: "\(pageID.uuidString.lowercased()).drawing")
  }

  private func noteDrawingDirectory(noteID: UUID) -> URL {
    directories.drawings
      .appending(path: noteID.uuidString.lowercased(), directoryHint: .isDirectory)
  }

  private func createDirectory(_ url: URL) throws {
    try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
  }

  private func replace(destination: URL, with temporary: URL) throws {
    guard fileManager.fileExists(atPath: destination.path) else {
      try fileManager.moveItem(at: temporary, to: destination)
      return
    }

    _ = try fileManager.replaceItemAt(
      destination,
      withItemAt: temporary,
      backupItemName: nil,
      options: .usingNewMetadataOnly)
  }
}

import Foundation
import PencilKit
import UIKit

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
  nonisolated let attachments: AttachmentRepository
  nonisolated let documents: DocumentRepository
  nonisolated let pendingSaves: PendingSaveRegistry
  nonisolated let exportsDirectory: URL
  nonisolated let backupsDirectory: URL
  nonisolated let drawingsDirectory: URL

  private let directories: AppDirectories
  private let fileManager: FileManager

  init(directories: AppDirectories, fileManager: FileManager = .default) {
    self.directories = directories
    self.fileManager = fileManager
    let attachments = AttachmentRepository(directories: directories)
    let documents = DocumentRepository(directories: directories)
    self.attachments = attachments
    self.documents = documents
    exportsDirectory = directories.exports
    backupsDirectory = directories.backups
    drawingsDirectory = directories.drawings
    previews = PreviewRepository(
      directories: directories,
      attachments: attachments,
      documents: documents)
    pendingSaves = PendingSaveRegistry()
  }

  func preview(for descriptor: PagePreviewDescriptor) async -> UIImage? {
    let cachedImage = await previews.preview(
      pageID: descriptor.pageID,
      noteID: descriptor.noteID,
      revision: descriptor.revision,
      paperStyle: descriptor.paperStyle)
    if let cachedImage { return cachedImage }

    guard !Task.isCancelled else { return nil }
    guard
      let drawing = try? load(pageID: descriptor.pageID, noteID: descriptor.noteID)
    else { return nil }
    try? await previews.store(
      drawing: drawing,
      elements: descriptor.elements,
      layout: descriptor.layout,
      paperStyle: descriptor.paperStyle,
      background: descriptor.background,
      pageID: descriptor.pageID,
      noteID: descriptor.noteID,
      revision: descriptor.revision)
    guard !Task.isCancelled else { return nil }
    return await previews.preview(
      pageID: descriptor.pageID,
      noteID: descriptor.noteID,
      revision: descriptor.revision,
      paperStyle: descriptor.paperStyle)
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
    await attachments.deletePage(pageID: pageID, noteID: noteID)
  }

  func deleteNote(noteID: UUID) async {
    try? fileManager.removeItem(at: noteDrawingDirectory(noteID: noteID))
    await previews.deleteNote(noteID: noteID)
    await attachments.deleteNote(noteID: noteID)
    await documents.deleteNote(noteID: noteID)
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

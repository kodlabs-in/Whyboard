import Foundation
import ImageIO
import PencilKit
import UniformTypeIdentifiers
import UIKit

enum PreviewStorageError: Error {
  case encodingFailed
  case writeFailed
}

actor PreviewRepository {
  private struct PreviewKey: Hashable {
    let noteID: UUID
    let pageID: UUID
  }

  private let directories: AppDirectories
  private let fileManager: FileManager
  private var newestStoredRevision: [PreviewKey: Int64] = [:]

  init(directories: AppDirectories, fileManager: FileManager = .default) {
    self.directories = directories
    self.fileManager = fileManager
  }

  func preview(pageID: UUID, noteID: UUID, revision: Int64) -> UIImage? {
    let url = previewURL(pageID: pageID, noteID: noteID, revision: revision)
    guard let data = try? Data(contentsOf: url) else { return nil }
    return UIImage(data: data)
  }

  func store(
    drawing: PKDrawing,
    pageID: UUID,
    noteID: UUID,
    revision: Int64
  ) throws {
    let key = PreviewKey(noteID: noteID, pageID: pageID)
    guard revision >= newestStoredRevision[key, default: -1] else { return }
    let noteDirectory = notePreviewDirectory(noteID: noteID)
    try createDirectory(noteDirectory)
    let data = try encodedPreview(for: drawing)
    let destination = previewURL(pageID: pageID, noteID: noteID, revision: revision)

    do {
      try data.write(to: destination, options: [.atomic, .completeFileProtection])
      newestStoredRevision[key] = revision
      removeObsoletePreviews(
        pageID: pageID,
        keeping: destination,
        noteDirectory: noteDirectory)
    } catch {
      throw PreviewStorageError.writeFailed
    }
  }

  func deletePage(pageID: UUID, noteID: UUID) {
    newestStoredRevision[PreviewKey(noteID: noteID, pageID: pageID)] = nil
    let directory = notePreviewDirectory(noteID: noteID)
    let prefix = "\(pageID.uuidString.lowercased())-"
    guard
      let urls = try? fileManager.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)
    else { return }

    for url in urls where url.lastPathComponent.hasPrefix(prefix) {
      try? fileManager.removeItem(at: url)
    }
  }

  func deleteNote(noteID: UUID) {
    newestStoredRevision = newestStoredRevision.filter { $0.key.noteID != noteID }
    try? fileManager.removeItem(at: notePreviewDirectory(noteID: noteID))
  }

  private func notePreviewDirectory(noteID: UUID) -> URL {
    directories.previews
      .appending(path: noteID.uuidString.lowercased(), directoryHint: .isDirectory)
  }

  private func previewURL(pageID: UUID, noteID: UUID, revision: Int64) -> URL {
    notePreviewDirectory(noteID: noteID)
      .appending(path: "\(pageID.uuidString.lowercased())-r\(revision).heic")
  }

  private func encodedPreview(for drawing: PKDrawing) throws -> Data {
    let image = drawing.image(
      from: CGRect(origin: .zero, size: CanonicalPage.size),
      scale: 0.25)
    guard let cgImage = image.cgImage else { throw PreviewStorageError.encodingFailed }

    let encodedData = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        encodedData,
        UTType.heic.identifier as CFString,
        1,
        nil)
    else {
      throw PreviewStorageError.encodingFailed
    }

    let options = [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary
    CGImageDestinationAddImage(destination, cgImage, options)
    guard CGImageDestinationFinalize(destination) else {
      throw PreviewStorageError.encodingFailed
    }
    return encodedData as Data
  }

  private func createDirectory(_ url: URL) throws {
    try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
  }

  private func removeObsoletePreviews(
    pageID: UUID,
    keeping destination: URL,
    noteDirectory: URL
  ) {
    let prefix = "\(pageID.uuidString.lowercased())-"
    guard
      let urls = try? fileManager.contentsOfDirectory(
        at: noteDirectory,
        includingPropertiesForKeys: nil)
    else { return }

    for url in urls where url != destination && url.lastPathComponent.hasPrefix(prefix) {
      try? fileManager.removeItem(at: url)
    }
  }
}

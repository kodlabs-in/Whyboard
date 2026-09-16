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
  private let renderer: PagePreviewRenderer
  private let imageCache = NSCache<NSString, UIImage>()
  private var cachedKeysByPage: [PreviewKey: Set<String>] = [:]
  private var newestStoredRevision: [PreviewKey: Int64] = [:]

  init(
    directories: AppDirectories,
    attachments: AttachmentRepository,
    documents: DocumentRepository,
    fileManager: FileManager = .default
  ) {
    self.directories = directories
    self.fileManager = fileManager
    renderer = PagePreviewRenderer(attachments: attachments, documents: documents)
    imageCache.totalCostLimit = 64 * 1_024 * 1_024
  }

  func preview(pageID: UUID, noteID: UUID, revision: Int64) -> UIImage? {
    let interval = AppSignpost.interval("Preview Decode")
    defer { interval.end() }
    let key = PreviewKey(noteID: noteID, pageID: pageID)
    let cacheKey = cacheKey(pageID: pageID, noteID: noteID, revision: revision)
    if let image = imageCache.object(forKey: cacheKey as NSString) {
      return image
    }
    let url = previewURL(pageID: pageID, noteID: noteID, revision: revision)
    guard let data = try? Data(contentsOf: url) else { return nil }
    guard !Task.isCancelled, let image = UIImage(data: data) else { return nil }
    cache(image, with: cacheKey, for: key)
    return image
  }

  func store(
    drawing: PKDrawing,
    elements: [WorkspaceElement] = [],
    layout: PagePreviewLayout = .page,
    paperStyle: NotePaperStyle = .white,
    background: ImportedPDFBackground? = nil,
    pageID: UUID,
    noteID: UUID,
    revision: Int64
  ) throws {
    let key = PreviewKey(noteID: noteID, pageID: pageID)
    guard revision >= newestStoredRevision[key, default: -1] else { return }
    let noteDirectory = notePreviewDirectory(noteID: noteID)
    try createDirectory(noteDirectory)
    let image = renderer.render(
      PagePreviewSnapshot(
        drawing: drawing,
        elements: elements,
        layout: layout,
        paperStyle: paperStyle,
        background: background),
      noteID: noteID,
      pageID: pageID)
    let data = try encodedPreview(for: image)
    let destination = previewURL(pageID: pageID, noteID: noteID, revision: revision)

    do {
      try data.write(to: destination, options: [.atomic, .completeFileProtection])
      newestStoredRevision[key] = revision
      removeCachedImages(for: key)
      cache(
        image,
        with: cacheKey(pageID: pageID, noteID: noteID, revision: revision),
        for: key)
      removeObsoletePreviews(
        pageID: pageID,
        keeping: destination,
        noteDirectory: noteDirectory)
    } catch {
      throw PreviewStorageError.writeFailed
    }
  }

  func deletePage(pageID: UUID, noteID: UUID) {
    let key = PreviewKey(noteID: noteID, pageID: pageID)
    newestStoredRevision[key] = nil
    removeCachedImages(for: key)
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
    removeCachedImages(noteID: noteID)
  }

  func clearMemoryCache() {
    imageCache.removeAllObjects()
    cachedKeysByPage.removeAll()
  }

  private func notePreviewDirectory(noteID: UUID) -> URL {
    directories.previews
      .appending(path: noteID.uuidString.lowercased(), directoryHint: .isDirectory)
  }

  private func previewURL(pageID: UUID, noteID: UUID, revision: Int64) -> URL {
    notePreviewDirectory(noteID: noteID)
      .appending(
        path:
          "\(pageID.uuidString.lowercased())-v\(PagePreviewRenderer.version)-r\(revision).heic")
  }

  private func encodedPreview(for image: UIImage) throws -> Data {
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

  private func cacheKey(pageID: UUID, noteID: UUID, revision: Int64) -> String {
    "\(noteID.uuidString)-\(pageID.uuidString)-\(revision)"
  }

  private func cache(_ image: UIImage, with cacheKey: String, for key: PreviewKey) {
    imageCache.setObject(
      image,
      forKey: cacheKey as NSString,
      cost: image.decodedByteCost)
    cachedKeysByPage[key, default: []].insert(cacheKey)
  }

  private func removeCachedImages(for key: PreviewKey) {
    for cacheKey in cachedKeysByPage.removeValue(forKey: key) ?? [] {
      imageCache.removeObject(forKey: cacheKey as NSString)
    }
  }

  private func removeCachedImages(noteID: UUID) {
    let keys = cachedKeysByPage.keys.filter { $0.noteID == noteID }
    for key in keys {
      removeCachedImages(for: key)
    }
  }
}

private extension UIImage {
  nonisolated var decodedByteCost: Int {
    guard let cgImage else { return 0 }
    return cgImage.bytesPerRow * cgImage.height
  }
}

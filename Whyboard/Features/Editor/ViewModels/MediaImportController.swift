import CoreTransferable
import Foundation
import Observation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ImportedImageAsset: Sendable {
  let filename: String
  let displayName: String
  let aspectRatio: Double
}

struct PhotoLibraryTransfer: Transferable, Sendable {
  let fileURL: URL
  let displayName: String

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(importedContentType: .image) { received in
      try copiedTransfer(from: received.file)
    }
  }

  private static func copiedTransfer(from source: URL) throws -> PhotoLibraryTransfer {
    let fileExtension = source.pathExtension.isEmpty ? "data" : source.pathExtension
    let destination = FileManager.default.temporaryDirectory
      .appending(path: "whyboard-import-\(UUID().uuidString).\(fileExtension)")
    try FileManager.default.copyItem(at: source, to: destination)
    return PhotoLibraryTransfer(
      fileURL: destination,
      displayName: source.deletingPathExtension().lastPathComponent)
  }
}

@MainActor
@Observable
final class MediaImportController {
  var isPhotoPickerPresented = false
  var isFileImporterPresented = false
  var selectedPhotoItem: PhotosPickerItem?
  private(set) var isImporting = false

  @ObservationIgnored private let attachments: AttachmentRepository
  @ObservationIgnored private var targetPageID: UUID?
  @ObservationIgnored private var noteID: UUID?
  @ObservationIgnored private var onImported: ((UUID, ImportedImageAsset) -> Void)?
  @ObservationIgnored private var onError: ((String) -> Void)?

  init(attachments: AttachmentRepository) {
    self.attachments = attachments
  }

  func configure(
    noteID: UUID,
    onImported: @escaping (UUID, ImportedImageAsset) -> Void,
    onError: @escaping (String) -> Void
  ) {
    self.noteID = noteID
    self.onImported = onImported
    self.onError = onError
  }

  func presentPhotoPicker(for pageID: UUID) {
    targetPageID = pageID
    isPhotoPickerPresented = true
  }

  func presentFileImporter(for pageID: UUID) {
    targetPageID = pageID
    isFileImporterPresented = true
  }

  func importSelectedPhoto() async {
    guard let item = selectedPhotoItem else { return }
    selectedPhotoItem = nil
    await performImport {
      guard let transfer = try await item.loadTransferable(type: PhotoLibraryTransfer.self) else {
        throw AttachmentStorageError.importFailed
      }
      defer { try? FileManager.default.removeItem(at: transfer.fileURL) }
      return try await storedImage(
        from: transfer.fileURL,
        displayName: transfer.displayName)
    }
  }

  func importFile(_ result: Result<URL, Error>) async {
    guard case .success(let url) = result else { return }
    await performImport {
      try await storedImage(
        from: url,
        displayName: url.deletingPathExtension().lastPathComponent)
    }
  }

  private func performImport(
    operation: () async throws -> ImportedImageAsset
  ) async {
    guard let targetPageID, noteID != nil else { return }
    isImporting = true
    defer { isImporting = false }

    do {
      let image = try await operation()
      onImported?(targetPageID, image)
    } catch {
      onError?(error.localizedDescription)
    }
  }

  private func storedImage(
    from url: URL,
    displayName: String
  ) async throws -> ImportedImageAsset {
    guard let noteID, let targetPageID else { throw AttachmentStorageError.importFailed }
    guard try isImage(url) else { throw AttachmentStorageError.unsupportedFile }
    let filename = try await attachments.importFile(
      at: url,
      noteID: noteID,
      pageID: targetPageID)
    let storedURL = attachments.fileURL(
      noteID: noteID,
      pageID: targetPageID,
      filename: filename)
    guard let image = UIImage(contentsOfFile: storedURL.path), image.size.height > 0 else {
      await attachments.delete(filename: filename, noteID: noteID, pageID: targetPageID)
      throw AttachmentStorageError.unsupportedFile
    }
    return ImportedImageAsset(
      filename: filename,
      displayName: displayName,
      aspectRatio: Double(image.size.width / image.size.height))
  }

  private func isImage(_ url: URL) throws -> Bool {
    let resourceType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
    let type = resourceType ?? UTType(filenameExtension: url.pathExtension)
    guard let type else { throw AttachmentStorageError.unsupportedFile }
    return type.conforms(to: .image)
  }
}

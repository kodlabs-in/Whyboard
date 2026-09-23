import CoreTransferable
import Foundation
import Observation
import PhotosUI
import SwiftUI
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

  static func copiedTransfer(from source: URL) throws -> PhotoLibraryTransfer {
    let fileExtension = source.pathExtension.isEmpty ? "data" : source.pathExtension
    let destination = FileManager.default.temporaryDirectory
      .appending(path: "whyboard-import-\(UUID().uuidString).\(fileExtension)")
    do {
      let byteSize = try ImportFilePreflight.inspectRegularFile(
        source,
        maximumBytes: ResourceLimits.maximumImageSourceBytes)
      try ImportFilePreflight.requireCapacity(
        for: byteSize,
        at: FileManager.default.temporaryDirectory)
      try FileManager.default.copyItem(at: source, to: destination)
      return PhotoLibraryTransfer(
        fileURL: destination,
        displayName: source.deletingPathExtension().lastPathComponent)
    } catch ImportFilePreflightError.invalidSource {
      try? FileManager.default.removeItem(at: destination)
      throw AttachmentStorageError.unsupportedFile
    } catch let error as ImportFilePreflightError {
      try? FileManager.default.removeItem(at: destination)
      switch error {
      case .resourceLimitExceeded, .insufficientStorage:
        throw AttachmentStorageError.resourceLimitExceeded
      case .invalidSource:
        throw AttachmentStorageError.unsupportedFile
      }
    } catch {
      try? FileManager.default.removeItem(at: destination)
      throw error
    }
  }
}

private struct MediaImportDestination: Sendable {
  let noteID: UUID
  let pageID: UUID
}

@MainActor
@Observable
final class MediaImportController {
  typealias ImageStore = @Sendable (URL, UUID, UUID) async throws -> StoredImageAttachment

  var isPhotoPickerPresented = false
  var isFileImporterPresented = false
  var selectedPhotoItem: PhotosPickerItem?
  private(set) var isImporting = false

  @ObservationIgnored private let attachments: AttachmentRepository
  @ObservationIgnored private let imageStore: ImageStore
  @ObservationIgnored private var configuredNoteID: UUID?
  @ObservationIgnored private var pendingDestination: MediaImportDestination?
  @ObservationIgnored private var onImported: ((UUID, ImportedImageAsset) -> Bool)?
  @ObservationIgnored private var onError: ((String) -> Void)?

  init(attachments: AttachmentRepository, imageStore: ImageStore? = nil) {
    self.attachments = attachments
    self.imageStore =
      imageStore ?? { source, noteID, pageID in
        try await attachments.importImage(at: source, noteID: noteID, pageID: pageID)
      }
  }

  func configure(
    noteID: UUID,
    onImported: @escaping (UUID, ImportedImageAsset) -> Bool,
    onError: @escaping (String) -> Void
  ) {
    configuredNoteID = noteID
    self.onImported = onImported
    self.onError = onError
  }

  func presentPhotoPicker(for pageID: UUID) {
    guard prepareDestination(pageID: pageID) else { return }
    isPhotoPickerPresented = true
  }

  func presentFileImporter(for pageID: UUID) {
    guard prepareDestination(pageID: pageID) else { return }
    isFileImporterPresented = true
  }

  func importSelectedPhoto() async {
    guard
      let item = selectedPhotoItem,
      let destination = beginImport()
    else { return }
    selectedPhotoItem = nil
    await performImport(destination: destination) {
      guard let transfer = try await item.loadTransferable(type: PhotoLibraryTransfer.self) else {
        throw AttachmentStorageError.importFailed
      }
      defer { try? FileManager.default.removeItem(at: transfer.fileURL) }
      return try await storedImage(
        from: transfer.fileURL,
        displayName: transfer.displayName,
        destination: destination)
    }
  }

  func importFile(_ result: Result<URL, Error>) async {
    guard let destination = beginImport() else { return }
    guard case .success(let url) = result else {
      isImporting = false
      if case .failure(let error) = result, !isCancellation(error) {
        onError?(error.localizedDescription)
      }
      return
    }
    await performImport(destination: destination) {
      try await storedImage(
        from: url,
        displayName: url.deletingPathExtension().lastPathComponent,
        destination: destination)
    }
  }

  private func performImport(
    destination: MediaImportDestination,
    operation: () async throws -> ImportedImageAsset
  ) async {
    defer { isImporting = false }

    do {
      let image = try await operation()
      guard onImported?(destination.pageID, image) == true else {
        await attachments.delete(
          filename: image.filename,
          noteID: destination.noteID,
          pageID: destination.pageID)
        throw AttachmentStorageError.importFailed
      }
    } catch is CancellationError {
      return
    } catch {
      onError?(error.localizedDescription)
    }
  }

  private func storedImage(
    from url: URL,
    displayName: String,
    destination: MediaImportDestination
  ) async throws -> ImportedImageAsset {
    let stored = try await imageStore(url, destination.noteID, destination.pageID)
    return ImportedImageAsset(
      filename: stored.filename,
      displayName: displayName,
      aspectRatio: stored.aspectRatio)
  }

  private func prepareDestination(pageID: UUID) -> Bool {
    guard
      !isImporting,
      !isPhotoPickerPresented,
      !isFileImporterPresented,
      let noteID = configuredNoteID
    else {
      onError?("Finish the current photo import before starting another one.")
      return false
    }
    pendingDestination = MediaImportDestination(noteID: noteID, pageID: pageID)
    return true
  }

  private func beginImport() -> MediaImportDestination? {
    guard !isImporting, let destination = pendingDestination else {
      onError?("Finish the current photo import before starting another one.")
      return nil
    }
    pendingDestination = nil
    isImporting = true
    return destination
  }

  private func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    let cocoaError = error as NSError
    return cocoaError.domain == NSCocoaErrorDomain
      && cocoaError.code == CocoaError.Code.userCancelled.rawValue
  }
}

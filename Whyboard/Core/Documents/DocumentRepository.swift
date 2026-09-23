import Foundation
import PDFKit

enum DocumentStorageError: LocalizedError, Sendable {
  case invalidPDF
  case encryptedPDF
  case resourceLimitExceeded
  case invalidPageGeometry
  case copyFailed
  case missingDocument

  var errorDescription: String? {
    switch self {
    case .invalidPDF:
      "Choose a valid PDF document."
    case .encryptedPDF:
      "Password-protected PDFs cannot be imported."
    case .resourceLimitExceeded:
      "This PDF is too large to import safely."
    case .invalidPageGeometry:
      "This PDF contains a page size Whyboard cannot display safely."
    case .copyFailed:
      "Whyboard couldn't copy this PDF into the note."
    case .missingDocument:
      "An imported PDF used by this note is missing."
    }
  }
}

struct StoredPDF: Sendable {
  let id: UUID
  let filename: String
  let pageCount: Int
}

nonisolated struct ValidatedPDF: Sendable {
  let pageCount: Int
  let byteSize: Int64
}

nonisolated enum PDFResourceValidator {
  static func validate(at source: URL, expectedPageCount: Int? = nil) throws -> ValidatedPDF {
    let byteSize: Int64
    do {
      byteSize = try ImportFilePreflight.inspectRegularFile(
        source,
        maximumBytes: ResourceLimits.maximumPDFSourceBytes)
    } catch ImportFilePreflightError.invalidSource {
      throw DocumentStorageError.invalidPDF
    } catch {
      throw DocumentStorageError.resourceLimitExceeded
    }
    try Task.checkCancellation()
    guard let document = PDFDocument(url: source) else {
      throw DocumentStorageError.invalidPDF
    }
    guard !document.isEncrypted else { throw DocumentStorageError.encryptedPDF }
    guard
      document.pageCount > 0,
      document.pageCount <= ResourceLimits.maximumPDFPages,
      expectedPageCount.map({ $0 == document.pageCount }) ?? true
    else { throw DocumentStorageError.resourceLimitExceeded }
    for index in 0..<document.pageCount {
      try Task.checkCancellation()
      guard let page = document.page(at: index) else {
        throw DocumentStorageError.invalidPDF
      }
      let bounds = page.bounds(for: .mediaBox)
      guard
        bounds.origin.x.isFinite,
        bounds.origin.y.isFinite,
        bounds.width.isFinite,
        bounds.height.isFinite,
        bounds.width > 0,
        bounds.height > 0,
        bounds.width <= ResourceLimits.maximumPDFPageDimension,
        bounds.height <= ResourceLimits.maximumPDFPageDimension
      else { throw DocumentStorageError.invalidPageGeometry }
    }
    return ValidatedPDF(pageCount: document.pageCount, byteSize: byteSize)
  }
}

actor DocumentRepository {
  nonisolated let rootDirectory: URL

  private let fileManager: FileManager

  init(directories: AppDirectories, fileManager: FileManager = .default) {
    rootDirectory = directories.documents
    self.fileManager = fileManager
  }

  func importPDF(at source: URL, noteID: UUID, documentID: UUID = UUID()) throws -> StoredPDF {
    let didAccess = source.startAccessingSecurityScopedResource()
    defer { if didAccess { source.stopAccessingSecurityScopedResource() } }

    do {
      let byteSize = try ImportFilePreflight.inspectRegularFile(
        source,
        maximumBytes: ResourceLimits.maximumPDFSourceBytes)
      try ImportFilePreflight.requireCapacity(for: byteSize, at: rootDirectory)
    } catch ImportFilePreflightError.invalidSource {
      throw DocumentStorageError.invalidPDF
    } catch let error as ImportFilePreflightError {
      switch error {
      case .resourceLimitExceeded, .insufficientStorage:
        throw DocumentStorageError.resourceLimitExceeded
      case .invalidSource:
        throw DocumentStorageError.invalidPDF
      }
    } catch {
      throw DocumentStorageError.copyFailed
    }

    let filename = "\(documentID.uuidString.lowercased()).pdf"
    let destination = fileURL(noteID: noteID, documentID: documentID)
    let staging = noteDirectory(noteID)
      .appending(path: ".import-\(UUID().uuidString.lowercased()).pdf")
    do {
      try fileManager.createDirectory(
        at: noteDirectory(noteID),
        withIntermediateDirectories: true)
      try fileManager.copyItem(at: source, to: staging)
    } catch {
      try? fileManager.removeItem(at: staging)
      throw DocumentStorageError.copyFailed
    }

    let validated: ValidatedPDF
    do {
      validated = try PDFResourceValidator.validate(at: staging)
    } catch {
      try? fileManager.removeItem(at: staging)
      throw error
    }
    do {
      guard !fileManager.fileExists(atPath: destination.path) else {
        throw DocumentStorageError.copyFailed
      }
      try fileManager.moveItem(at: staging, to: destination)
      return StoredPDF(id: documentID, filename: filename, pageCount: validated.pageCount)
    } catch {
      try? fileManager.removeItem(at: staging)
      throw DocumentStorageError.copyFailed
    }
  }

  func copyDocument(
    _ sourceID: UUID,
    fromNoteID: UUID,
    toNoteID: UUID,
    destinationID: UUID
  ) throws {
    let source = fileURL(noteID: fromNoteID, documentID: sourceID)
    guard fileManager.fileExists(atPath: source.path) else {
      throw DocumentStorageError.missingDocument
    }
    let destination = fileURL(noteID: toNoteID, documentID: destinationID)
    do {
      try fileManager.createDirectory(
        at: noteDirectory(toNoteID),
        withIntermediateDirectories: true)
      try fileManager.copyItem(at: source, to: destination)
    } catch {
      throw DocumentStorageError.copyFailed
    }
  }

  nonisolated func fileURL(noteID: UUID, documentID: UUID) -> URL {
    noteDirectory(noteID)
      .appending(path: "\(documentID.uuidString.lowercased()).pdf")
  }

  func deleteNote(noteID: UUID) {
    try? fileManager.removeItem(at: noteDirectory(noteID))
  }

  private nonisolated func noteDirectory(_ noteID: UUID) -> URL {
    rootDirectory
      .appending(path: noteID.uuidString.lowercased(), directoryHint: .isDirectory)
  }
}

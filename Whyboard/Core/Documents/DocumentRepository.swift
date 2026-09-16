import Foundation
import PDFKit

enum DocumentStorageError: LocalizedError, Sendable {
  case invalidPDF
  case encryptedPDF
  case copyFailed
  case missingDocument

  var errorDescription: String? {
    switch self {
    case .invalidPDF:
      "Choose a valid PDF document."
    case .encryptedPDF:
      "Password-protected PDFs cannot be imported."
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
    guard let document = PDFDocument(url: source), document.pageCount > 0 else {
      throw DocumentStorageError.invalidPDF
    }
    guard !document.isEncrypted else { throw DocumentStorageError.encryptedPDF }

    let filename = "\(documentID.uuidString.lowercased()).pdf"
    let destination = fileURL(noteID: noteID, documentID: documentID)
    do {
      try fileManager.createDirectory(
        at: noteDirectory(noteID),
        withIntermediateDirectories: true)
      try fileManager.copyItem(at: source, to: destination)
      return StoredPDF(id: documentID, filename: filename, pageCount: document.pageCount)
    } catch {
      try? fileManager.removeItem(at: destination)
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

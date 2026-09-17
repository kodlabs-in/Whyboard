import Foundation
import SwiftData

enum PDFImportError: LocalizedError {
  case cancelled
  case publishFailed

  var errorDescription: String? {
    switch self {
    case .cancelled:
      "PDF import was cancelled."
    case .publishFailed:
      "Whyboard couldn't publish the imported notebook."
    }
  }
}

@MainActor
struct PDFImportService {
  let drawingRepository: DrawingRepository

  func importPDF(
    at source: URL,
    folderID: UUID,
    paperStyle: NotePaperStyle = .defaultStyle,
    existingNotes: [Note],
    context: ModelContext,
    onProgress: (Double) -> Void = { _ in }
  ) async throws -> UUID {
    let note = makeNote(
      source: source,
      folderID: folderID,
      paperStyle: paperStyle,
      existingNotes: existingNotes)
    do {
      let stored = try await drawingRepository.documents.importPDF(
        at: source,
        noteID: note.id)
      try Task.checkCancellation()
      let document = ImportedDocument(
        id: stored.id,
        noteID: note.id,
        filename: stored.filename,
        pageCount: stored.pageCount)
      let pages = try await makePages(
        noteID: note.id,
        documentID: stored.id,
        pageCount: stored.pageCount,
        onProgress: onProgress)
      try publish(note: note, document: document, pages: pages, context: context)
      onProgress(1)
      return note.id
    } catch is CancellationError {
      await drawingRepository.deleteNote(noteID: note.id)
      throw PDFImportError.cancelled
    } catch {
      await drawingRepository.deleteNote(noteID: note.id)
      throw error
    }
  }

  private func makeNote(
    source: URL,
    folderID: UUID,
    paperStyle: NotePaperStyle,
    existingNotes: [Note]
  ) -> Note {
    let sourceTitle = source.deletingPathExtension().lastPathComponent
    let baseTitle = sourceTitle.isEmpty ? "Imported PDF" : sourceTitle
    let conflicts = existingNotes.filter { $0.folderID == folderID }.map(\.title)
    let title = uniqueTitle(baseTitle, existingTitles: conflicts)
    return Note(
      folderID: folderID,
      title: title,
      paperStyle: paperStyle,
      kind: .infinitePages)
  }

  private func uniqueTitle(_ title: String, existingTitles: [String]) -> String {
    let folded = Set(existingTitles.map { $0.folding(options: .caseInsensitive, locale: .current) })
    guard folded.contains(title.folding(options: .caseInsensitive, locale: .current)) else {
      return title
    }
    return DuplicateTitleResolver.title(for: title, existingTitles: existingTitles)
  }

  private func makePages(
    noteID: UUID,
    documentID: UUID,
    pageCount: Int,
    onProgress: (Double) -> Void
  ) async throws -> [Page] {
    var pages: [Page] = []
    pages.reserveCapacity(pageCount)
    for index in 0..<pageCount {
      try Task.checkCancellation()
      let page = Page(noteID: noteID, sortOrder: index)
      page.importedDocumentID = documentID
      page.importedDocumentPageIndex = index
      pages.append(page)
      if index.isMultiple(of: 25) {
        onProgress(Double(index) / Double(max(pageCount, 1)))
        await Task.yield()
      }
    }
    return pages
  }

  private func publish(
    note: Note,
    document: ImportedDocument,
    pages: [Page],
    context: ModelContext
  ) throws {
    context.insert(note)
    context.insert(document)
    pages.forEach(context.insert)
    do {
      try context.save()
    } catch {
      context.rollback()
      throw PDFImportError.publishFailed
    }
  }
}

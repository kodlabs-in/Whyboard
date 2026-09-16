import Foundation
import SwiftData

enum DuplicationError: LocalizedError, Sendable {
  case missingSourcePage
  case sourceSaveFailed
  case metadataSaveFailed

  var errorDescription: String? {
    switch self {
    case .missingSourcePage:
      "Whyboard could not find the page to duplicate."
    case .sourceSaveFailed:
      "Save the source note before duplicating it."
    case .metadataSaveFailed:
      "Whyboard could not publish the duplicate. The original was left unchanged."
    }
  }
}

enum DuplicateTitleResolver {
  static func title(for original: String, existingTitles: [String]) -> String {
    let normalizedTitles = Set(existingTitles.map(normalized))
    let baseTitle = "\(original) Copy"
    guard normalizedTitles.contains(normalized(baseTitle)) else { return baseTitle }

    var suffix = 2
    while normalizedTitles.contains(normalized("\(baseTitle) \(suffix)")) {
      suffix += 1
    }
    return "\(baseTitle) \(suffix)"
  }

  private static func normalized(_ title: String) -> String {
    title.folding(
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: .current)
  }
}

@MainActor
struct DuplicationService {
  let drawingRepository: DrawingRepository

  func duplicatePage(
    _ source: Page,
    in pages: [Page],
    note: Note,
    context: ModelContext
  ) async throws -> UUID {
    try await flushSource(note.id)
    let orderedPages = PageOrdering.ordered(pages)
    guard let sourceIndex = orderedPages.firstIndex(where: { $0.id == source.id }) else {
      throw DuplicationError.missingSourcePage
    }

    let copy = pageCopy(
      of: source,
      noteID: note.id,
      sortOrder: sourceIndex + 1)
    let copyID = copy.id
    do {
      try await copyPayload(from: source, sourceNoteID: note.id, to: copy)
      try publishPage(copy, after: sourceIndex, pages: orderedPages, note: note, context: context)
      return copyID
    } catch {
      await drawingRepository.deletePage(pageID: copyID, noteID: note.id)
      throw error
    }
  }

  func duplicateNote(
    _ source: Note,
    pages: [Page],
    notes: [Note],
    documents: [ImportedDocument] = [],
    context: ModelContext
  ) async throws -> UUID {
    try await flushSource(source.id)
    let copy = noteCopy(of: source, notes: notes)
    let copyID = copy.id
    let sourceDocuments = documents.filter { $0.noteID == source.id }
    let documentCopies = sourceDocuments.map { documentCopy(of: $0, noteID: copy.id) }
    let documentIDMap = Dictionary(
      uniqueKeysWithValues: zip(sourceDocuments, documentCopies).map { ($0.id, $1.id) })
    let sourcePages = PageOrdering.ordered(pages.filter { $0.noteID == source.id })
    let pageCopies = sourcePages.enumerated().map { index, page in
      pageCopy(
        of: page,
        noteID: copy.id,
        sortOrder: index,
        documentIDMap: documentIDMap)
    }

    do {
      try await copyDocuments(
        sources: sourceDocuments,
        copies: documentCopies,
        sourceNoteID: source.id,
        destinationNoteID: copy.id)
      for (sourcePage, pageCopy) in zip(sourcePages, pageCopies) {
        try await copyPayload(
          from: sourcePage,
          sourceNoteID: source.id,
          to: pageCopy)
      }
      try publishNote(
        copy,
        pages: pageCopies,
        documents: documentCopies,
        context: context)
      return copyID
    } catch {
      await drawingRepository.deleteNote(noteID: copyID)
      throw error
    }
  }

  private func pageCopy(
    of source: Page,
    noteID: UUID,
    sortOrder: Int,
    documentIDMap: [UUID: UUID]? = nil
  ) -> Page {
    let copy = Page(
      noteID: noteID,
      sortOrder: sortOrder,
      contentRevision: source.contentRevision)
    copy.workspaceElementsData = source.workspaceElementsData
    copy.importedDocumentID = mappedDocumentID(
      source.importedDocumentID,
      using: documentIDMap)
    copy.importedDocumentPageIndex = source.importedDocumentPageIndex
    return copy
  }

  private func mappedDocumentID(
    _ sourceID: UUID?,
    using documentIDMap: [UUID: UUID]?
  ) -> UUID? {
    guard let sourceID, let documentIDMap else { return sourceID }
    return documentIDMap[sourceID]
  }

  private func documentCopy(
    of source: ImportedDocument,
    noteID: UUID
  ) -> ImportedDocument {
    ImportedDocument(
      noteID: noteID,
      pageCount: source.pageCount,
      formatVersion: source.formatVersion)
  }

  private func copyDocuments(
    sources: [ImportedDocument],
    copies: [ImportedDocument],
    sourceNoteID: UUID,
    destinationNoteID: UUID
  ) async throws {
    for (source, copy) in zip(sources, copies) {
      try await drawingRepository.documents.copyDocument(
        source.id,
        fromNoteID: sourceNoteID,
        toNoteID: destinationNoteID,
        destinationID: copy.id)
    }
  }

  private func flushSource(_ noteID: UUID) async throws {
    guard await drawingRepository.pendingSaves.flush(noteID: noteID) else {
      throw DuplicationError.sourceSaveFailed
    }
  }

  private func noteCopy(of source: Note, notes: [Note]) -> Note {
    let titles = notes.filter { $0.folderID == source.folderID }.map(\.title)
    let copy = Note(
      folderID: source.folderID,
      title: DuplicateTitleResolver.title(for: source.title, existingTitles: titles),
      paperStyle: source.paperStyle,
      kind: source.kind)
    copy.canvasOffsetX = source.canvasOffsetX
    copy.canvasOffsetY = source.canvasOffsetY
    copy.canvasZoomScale = source.canvasZoomScale
    return copy
  }

  private func copyPayload(
    from source: Page,
    sourceNoteID: UUID,
    to destination: Page
  ) async throws {
    let drawing = try await drawingRepository.load(
      pageID: source.id,
      noteID: sourceNoteID)
    try await drawingRepository.save(
      drawing,
      pageID: destination.id,
      noteID: destination.noteID)
    let attachmentFilenames = Set(
      WorkspaceElementCoding.decode(source.workspaceElementsData).compactMap(\.assetFilename))
    try await drawingRepository.attachments.copyFiles(
      attachmentFilenames,
      fromNoteID: sourceNoteID,
      fromPageID: source.id,
      toNoteID: destination.noteID,
      toPageID: destination.id)
  }

  private func publishPage(
    _ copy: Page,
    after sourceIndex: Int,
    pages: [Page],
    note: Note,
    context: ModelContext
  ) throws {
    var reorderedPages = pages
    reorderedPages.insert(copy, at: sourceIndex + 1)
    context.insert(copy)
    PageOrdering.renumber(reorderedPages)
    note.updatedAt = Date()
    try save(context)
  }

  private func publishNote(
    _ note: Note,
    pages: [Page],
    documents: [ImportedDocument],
    context: ModelContext
  ) throws {
    context.insert(note)
    documents.forEach(context.insert)
    for page in pages {
      context.insert(page)
    }
    try save(context)
  }

  private func save(_ context: ModelContext) throws {
    do {
      try context.save()
    } catch {
      context.rollback()
      throw DuplicationError.metadataSaveFailed
    }
  }
}

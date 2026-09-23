import Foundation
import SwiftData

nonisolated struct LibraryPageCover: Sendable {
  let pageID: UUID
  let noteID: UUID
  let sortOrder: Int
  let contentRevision: Int64
  let workspaceElementsData: Data?
  let importedDocumentID: UUID?
  let importedDocumentPageIndex: Int?

  init(page: Page) {
    pageID = page.id
    noteID = page.noteID
    sortOrder = page.sortOrder
    contentRevision = page.contentRevision
    workspaceElementsData = page.workspaceElementsData
    importedDocumentID = page.importedDocumentID
    importedDocumentPageIndex = page.importedDocumentPageIndex
  }
}

nonisolated struct LibraryPageSummary: Sendable {
  private(set) var pageCounts: [UUID: Int]
  private(set) var coverPages: [UUID: LibraryPageCover]

  init(pages: [Page] = []) {
    pageCounts = [:]
    coverPages = [:]
    for page in pages {
      pageCounts[page.noteID, default: 0] += 1
      if page.sortOrder < (coverPages[page.noteID]?.sortOrder ?? .max) {
        coverPages[page.noteID] = LibraryPageCover(page: page)
      }
    }
  }

  init(pageCounts: [UUID: Int], coverPages: [UUID: LibraryPageCover]) {
    self.pageCounts = pageCounts
    self.coverPages = coverPages
  }
}

@ModelActor
actor LibraryPageSummaryStore {
  static let defaultBatchSize = 256

  func load(
    batchSize requestedBatchSize: Int = defaultBatchSize
  ) async throws -> LibraryPageSummary {
    let batchSize = max(1, requestedBatchSize)
    var pageCounts: [UUID: Int] = [:]
    var coverReferences: [UUID: LibraryPageReference] = [:]
    var offset = 0

    while true {
      try Task.checkCancellation()
      var descriptor = FetchDescriptor<Page>(sortBy: [SortDescriptor(\Page.id)])
      descriptor.fetchLimit = batchSize
      descriptor.fetchOffset = offset
      descriptor.propertiesToFetch = [\Page.id, \Page.noteID, \Page.sortOrder]
      let pages = try modelContext.fetch(descriptor)
      for page in pages {
        pageCounts[page.noteID, default: 0] += 1
        if page.sortOrder < (coverReferences[page.noteID]?.sortOrder ?? .max) {
          coverReferences[page.noteID] = LibraryPageReference(page: page)
        }
      }
      guard pages.count == batchSize else { break }
      offset += pages.count
      await Task.yield()
    }

    let coverPages = try await loadCovers(
      Array(coverReferences.values),
      batchSize: batchSize)
    return LibraryPageSummary(pageCounts: pageCounts, coverPages: coverPages)
  }

  private func loadCovers(
    _ references: [LibraryPageReference],
    batchSize: Int
  ) async throws -> [UUID: LibraryPageCover] {
    var covers: [UUID: LibraryPageCover] = [:]
    for start in stride(from: 0, to: references.count, by: batchSize) {
      try Task.checkCancellation()
      let end = min(start + batchSize, references.count)
      let pageIDs = references[start..<end].map(\.pageID)
      let predicate = #Predicate<Page> { pageIDs.contains($0.id) }
      let pages = try modelContext.fetch(FetchDescriptor<Page>(predicate: predicate))
      for page in pages {
        covers[page.noteID] = LibraryPageCover(page: page)
      }
      if end < references.count {
        await Task.yield()
      }
    }
    return covers
  }
}

private nonisolated struct LibraryPageReference: Sendable {
  let pageID: UUID
  let sortOrder: Int

  init(page: Page) {
    pageID = page.id
    sortOrder = page.sortOrder
  }
}

extension PagePreviewDescriptor {
  init(
    coverPage: LibraryPageCover,
    note: Note,
    paperStyle: NotePaperStyle = .white
  ) {
    noteID = coverPage.noteID
    pageID = coverPage.pageID
    revision = coverPage.contentRevision
    elements = WorkspaceElementCoding.decode(coverPage.workspaceElementsData)
    layout = PagePreviewLayout(note: note)
    self.paperStyle = paperStyle == .automatic ? .white : paperStyle
    let importedDocumentID = coverPage.importedDocumentID
    let importedPageIndex = coverPage.importedDocumentPageIndex
    if let importedDocumentID, let importedPageIndex {
      background = ImportedPDFBackground(
        documentID: importedDocumentID,
        pageIndex: importedPageIndex
      )
    } else {
      background = nil
    }
  }
}

extension ImportedPDFBackground {
  init(documentID: UUID, pageIndex: Int) {
    self.documentID = documentID
    self.pageIndex = pageIndex
  }
}

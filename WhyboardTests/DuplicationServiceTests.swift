import Foundation
import SwiftData
import Testing

@testable import Whyboard

@MainActor
struct DuplicationServiceTests {
  @Test func pageDuplicateIsAdjacentAndOwnsIndependentFiles() async throws {
    let container = try makeContainer()
    let context = container.mainContext
    let directories = try AppDirectories.make(isTesting: true)
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let repository = DrawingRepository(directories: directories)
    let note = Note(folderID: UUID(), title: "Biology")
    let source = Page(noteID: note.id, sortOrder: 0, contentRevision: 4)
    let following = Page(noteID: note.id, sortOrder: 1)
    context.insert(note)
    context.insert(source)
    context.insert(following)

    let assetData = Data([11, 22, 33, 44])
    let importedFilename = try await importAttachment(
      assetData,
      noteID: note.id,
      pageID: source.id,
      directories: directories,
      repository: repository)
    let orphanedFilename = try await importAttachment(
      Data([55]),
      noteID: note.id,
      pageID: source.id,
      directories: directories,
      repository: repository)
    source.workspaceElementsData = try WorkspaceElementCoding.encode([
      imageElement(filename: importedFilename)
    ])
    try context.save()

    let duplicateID = try await DuplicationService(drawingRepository: repository)
      .duplicatePage(source, in: [source, following], note: note, context: context)
    let pages = PageOrdering.ordered(try context.fetch(FetchDescriptor<Page>()))
    let duplicate = try #require(pages.first(where: { $0.id == duplicateID }))

    #expect(pages.map(\.id) == [source.id, duplicateID, following.id])
    #expect(pages.map(\.sortOrder) == [0, 1, 2])
    #expect(duplicate.noteID == note.id)
    #expect(duplicate.contentRevision == source.contentRevision)
    #expect(duplicate.workspaceElementsData == source.workspaceElementsData)

    try verifyAttachmentIndependence(
      pages: (source, duplicate),
      noteID: note.id,
      filenames: (importedFilename, orphanedFilename),
      sourceData: assetData,
      repository: repository)
  }

  @Test func noteDuplicateCopiesKindPagesAndPredictableTitle() async throws {
    let container = try makeContainer()
    let context = container.mainContext
    let directories = try AppDirectories.make(isTesting: true)
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let repository = DrawingRepository(directories: directories)
    let folderID = UUID()
    let source = Note(
      folderID: folderID,
      title: "Ideas",
      paperStyle: .black,
      kind: .infiniteCanvas)
    source.canvasOffsetX = 120
    source.canvasOffsetY = 80
    source.canvasZoomScale = 1.5
    let first = Page(noteID: source.id, sortOrder: 0, contentRevision: 2)
    let second = Page(noteID: source.id, sortOrder: 1, contentRevision: 5)
    let existingCopy = Note(folderID: folderID, title: "Ideas Copy")
    let existingSecondCopy = Note(folderID: folderID, title: "Ideas Copy 2")
    [source, existingCopy, existingSecondCopy].forEach(context.insert)
    [first, second].forEach(context.insert)
    try context.save()

    let duplicateID = try await DuplicationService(drawingRepository: repository)
      .duplicateNote(
        source,
        pages: [second, first],
        notes: [source, existingCopy, existingSecondCopy],
        context: context)
    let notes = try context.fetch(FetchDescriptor<Note>())
    let duplicate = try #require(notes.first(where: { $0.id == duplicateID }))
    let duplicatePages = PageOrdering.ordered(
      try context.fetch(FetchDescriptor<Page>()).filter { $0.noteID == duplicateID })

    #expect(duplicate.title == "Ideas Copy 3")
    #expect(duplicate.folderID == source.folderID)
    #expect(duplicate.kind == .infiniteCanvas)
    #expect(duplicate.paperStyle == .black)
    #expect(duplicate.canvasOffsetX == source.canvasOffsetX)
    #expect(duplicate.canvasOffsetY == source.canvasOffsetY)
    #expect(duplicate.canvasZoomScale == source.canvasZoomScale)
    #expect(duplicate.lastOpenedAt == nil)
    #expect(duplicatePages.count == 2)
    #expect(duplicatePages.map(\.sortOrder) == [0, 1])
    #expect(Set(duplicatePages.map(\.id)).isDisjoint(with: [first.id, second.id]))
    #expect(duplicatePages.map(\.contentRevision) == [2, 5])
  }

  @Test func duplicateTitlesIgnoreCaseAndDiacritics() {
    let title = DuplicateTitleResolver.title(
      for: "Résumé",
      existingTitles: ["résumé copy", "Resume Copy 2"])

    #expect(title == "Résumé Copy 3")
  }

  @Test func duplicationStopsWhenTheSourceCannotFlush() async throws {
    let container = try makeContainer()
    let context = container.mainContext
    let directories = try AppDirectories.make(isTesting: true)
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let repository = DrawingRepository(directories: directories)
    let note = Note(folderID: UUID())
    let page = Page(noteID: note.id, sortOrder: 0)
    context.insert(note)
    context.insert(page)
    try context.save()
    repository.pendingSaves.register(noteID: note.id) { false }

    await #expect(throws: DuplicationError.self) {
      try await DuplicationService(drawingRepository: repository)
        .duplicatePage(page, in: [page], note: note, context: context)
    }
    #expect(try context.fetchCount(FetchDescriptor<Page>()) == 1)
  }

  @Test func noteDuplicateRemapsAndCopiesImportedPDFStorage() async throws {
    let container = try makeContainer()
    let context = container.mainContext
    let directories = try AppDirectories.make(isTesting: true)
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let repository = DrawingRepository(directories: directories)
    let source = Note(folderID: UUID(), title: "Worksheet")
    let document = ImportedDocument(noteID: source.id, pageCount: 2)
    let page = Page(noteID: source.id, sortOrder: 0)
    page.importedDocumentID = document.id
    page.importedDocumentPageIndex = 1
    context.insert(source)
    context.insert(document)
    context.insert(page)
    let documentURL = repository.documents.fileURL(
      noteID: source.id,
      documentID: document.id)
    try FileManager.default.createDirectory(
      at: documentURL.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    let sourceBytes = Data([37, 80, 68, 70, 45, 49])
    try sourceBytes.write(to: documentURL)
    try context.save()

    let duplicateID = try await DuplicationService(drawingRepository: repository)
      .duplicateNote(
        source,
        pages: [page],
        notes: [source],
        documents: [document],
        context: context)
    let duplicateDocument = try #require(
      try context.fetch(FetchDescriptor<ImportedDocument>()).first {
        $0.noteID == duplicateID
      })
    let duplicatePage = try #require(
      try context.fetch(FetchDescriptor<Page>()).first { $0.noteID == duplicateID })
    let duplicateURL = repository.documents.fileURL(
      noteID: duplicateID,
      documentID: duplicateDocument.id)

    #expect(duplicateDocument.id != document.id)
    #expect(duplicatePage.importedDocumentID == duplicateDocument.id)
    #expect(duplicatePage.importedDocumentPageIndex == 1)
    #expect(try Data(contentsOf: duplicateURL) == sourceBytes)
  }

  private func importAttachment(
    _ data: Data,
    noteID: UUID,
    pageID: UUID,
    directories: AppDirectories,
    repository: DrawingRepository
  ) async throws -> String {
    let source = directories.root.appending(path: "duplication-source.png")
    try data.write(to: source, options: .atomic)
    return try await repository.attachments.importFile(
      at: source,
      noteID: noteID,
      pageID: pageID)
  }

  private func imageElement(filename: String) -> WorkspaceElement {
    WorkspaceElement(
      kind: .image,
      frame: WorkspaceElementFrame(
        center: CGPoint(x: 300, y: 400),
        size: CGSize(width: 240, height: 180)),
      zIndex: 0,
      assetFilename: filename,
      displayName: "Diagram",
      aspectRatio: 4.0 / 3.0)
  }

  private func verifyAttachmentIndependence(
    pages: (source: Page, duplicate: Page),
    noteID: UUID,
    filenames: (referenced: String, orphaned: String),
    sourceData: Data,
    repository: DrawingRepository
  ) throws {
    let sourceAsset = repository.attachments.fileURL(
      noteID: noteID,
      pageID: pages.source.id,
      filename: filenames.referenced)
    let duplicateAsset = repository.attachments.fileURL(
      noteID: noteID,
      pageID: pages.duplicate.id,
      filename: filenames.referenced)
    let duplicateOrphan = repository.attachments.fileURL(
      noteID: noteID,
      pageID: pages.duplicate.id,
      filename: filenames.orphaned)
    #expect(try Data(contentsOf: duplicateAsset) == sourceData)
    #expect(!FileManager.default.fileExists(atPath: duplicateOrphan.path))
    try Data([99]).write(to: duplicateAsset, options: .atomic)
    #expect(try Data(contentsOf: sourceAsset) == sourceData)
  }

  private func makeContainer() throws -> ModelContainer {
    let schema = Schema([Folder.self, Note.self, Page.self, ImportedDocument.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
  }
}

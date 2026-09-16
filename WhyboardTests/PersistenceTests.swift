import Foundation
import PencilKit
import SwiftData
import Testing

@testable import Whyboard

@MainActor
struct PersistenceTests {
  private struct StoredIdentities {
    let folderID: UUID
    let noteID: UUID
    let pageID: UUID
  }

  @Test func seedingCreatesExactlyOneUnfiledFolder() throws {
    let schema = Schema([Folder.self, Note.self, Page.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])

    try LibrarySeeder.seedIfNeeded(in: container.mainContext)
    try LibrarySeeder.seedIfNeeded(in: container.mainContext)

    let folders = try container.mainContext.fetch(FetchDescriptor<Folder>())
    #expect(folders.count == 1)
    #expect(folders.first?.name == "Unfiled Notes")
    #expect(folders.first?.isSystem == true)
  }

  @Test func metadataSurvivesAContainerRelaunch() throws {
    let directories = try AppDirectories.make(isTesting: true)
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let schema = Schema([Folder.self, Note.self, Page.self])
    let storeURL = directories.metadata.appending(path: "Relaunch.store")
    let identities = try seedPersistentStore(schema: schema, url: storeURL)
    let configuration = ModelConfiguration(
      "Relaunch",
      schema: schema,
      url: storeURL,
      cloudKitDatabase: .none)

    let relaunched = try ModelContainer(for: schema, configurations: [configuration])
    let context = relaunched.mainContext
    let folders = try context.fetch(FetchDescriptor<Folder>())
    let notes = try context.fetch(FetchDescriptor<Note>())
    let pages = try context.fetch(FetchDescriptor<Page>())

    #expect(folders.map(\.id) == [identities.folderID])
    #expect(notes.map(\.id) == [identities.noteID])
    #expect(pages.map(\.id) == [identities.pageID])
  }

  @Test func drawingRoundTripsThroughAtomicStorage() async throws {
    let directories = try AppDirectories.make(isTesting: true)
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let repository = DrawingRepository(directories: directories)
    let noteID = UUID()
    let pageID = UUID()
    let drawing = PKDrawing()

    try await repository.save(drawing, pageID: pageID, noteID: noteID)
    let loaded = try await repository.load(pageID: pageID, noteID: noteID)

    #expect(loaded == drawing)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directories.recovery.path).isEmpty)
  }

  @Test func missingDrawingLoadsAsABlankPage() async throws {
    let directories = try AppDirectories.make(isTesting: true)
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let repository = DrawingRepository(directories: directories)

    let drawing = try await repository.load(pageID: UUID(), noteID: UUID())

    #expect(drawing.strokes.isEmpty)
  }

  @Test func pageSessionCoalescesChangesAndIncrementsRevisionAfterSaving() async throws {
    let directories = try AppDirectories.make(isTesting: true)
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let repository = DrawingRepository(directories: directories)
    let note = Note(folderID: UUID())
    let page = Page(noteID: note.id, sortOrder: 0)
    var metadataSaveCount = 0
    let session = PageSession(
      page: page,
      note: note,
      drawingRepository: repository,
      saveMetadata: { metadataSaveCount += 1 },
      onStateChange: {})

    await session.loadIfNeeded()
    session.drawingDidChange(PKDrawing())
    session.drawingDidChange(PKDrawing())
    let saved = await session.flush()

    #expect(saved)
    #expect(session.state == .clean)
    #expect(page.contentRevision == 1)
    #expect(metadataSaveCount == 1)
  }

  @Test func previewCacheIsRevisionKeyedAndDisposable() async throws {
    let directories = try AppDirectories.make(isTesting: true)
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let repository = DrawingRepository(directories: directories)
    let noteID = UUID()
    let pageID = UUID()
    let drawing = PKDrawing()
    try await repository.save(drawing, pageID: pageID, noteID: noteID)
    let previews = repository.previews

    try await previews.store(
      drawing: drawing,
      pageID: pageID,
      noteID: noteID,
      revision: 1)
    #expect(await previews.preview(pageID: pageID, noteID: noteID, revision: 1) != nil)

    try await previews.store(
      drawing: drawing,
      pageID: pageID,
      noteID: noteID,
      revision: 2)
    #expect(await previews.preview(pageID: pageID, noteID: noteID, revision: 1) == nil)
    #expect(await previews.preview(pageID: pageID, noteID: noteID, revision: 2) != nil)

    let currentPreview = directories.previews
      .appending(path: noteID.uuidString.lowercased(), directoryHint: .isDirectory)
      .appending(
        path:
          "\(pageID.uuidString.lowercased())-v\(PagePreviewRenderer.version)-r2.heic")
    try FileManager.default.removeItem(at: currentPreview)
    await previews.clearMemoryCache()
    #expect(await previews.preview(pageID: pageID, noteID: noteID, revision: 2) == nil)
    #expect(try await repository.load(pageID: pageID, noteID: noteID) == drawing)
  }

  @Test func previewCompositesWorkspaceObjectsWithInk() async throws {
    let directories = try AppDirectories.make(isTesting: true)
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let repository = DrawingRepository(directories: directories)
    let noteID = UUID()
    let pageID = UUID()
    let drawing = PKDrawing()

    try await repository.previews.store(
      drawing: drawing,
      pageID: pageID,
      noteID: noteID,
      revision: 1)
    let drawingOnlyResult = await repository.previews.preview(
      pageID: pageID,
      noteID: noteID,
      revision: 1)
    let drawingOnly = try #require(drawingOnlyResult)

    let shape = WorkspaceElement(
      kind: .shape,
      frame: WorkspaceElementFrame(
        center: CGPoint(x: 300, y: 400),
        size: CGSize(width: 240, height: 180)),
      zIndex: 0,
      shapeKind: .ellipse,
      color: .orange)
    try await repository.previews.store(
      drawing: drawing,
      elements: [shape],
      pageID: pageID,
      noteID: noteID,
      revision: 2)
    let compositedResult = await repository.previews.preview(
      pageID: pageID,
      noteID: noteID,
      revision: 2)
    let composited = try #require(compositedResult)

    #expect(drawingOnly.pngData() != composited.pngData())
  }

  @Test func damagedDrawingReportsAnErrorWithoutReplacingTheFile() async throws {
    let directories = try AppDirectories.make(isTesting: true)
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let noteID = UUID()
    let pageID = UUID()
    let noteDirectory = directories.drawings.appending(
      path: noteID.uuidString.lowercased(),
      directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: noteDirectory, withIntermediateDirectories: true)
    let drawingURL = noteDirectory.appending(path: "\(pageID.uuidString.lowercased()).drawing")
    let damagedData = Data("not-a-pencil-drawing".utf8)
    try damagedData.write(to: drawingURL)
    let repository = DrawingRepository(directories: directories)

    await #expect(throws: DrawingStorageError.self) {
      try await repository.load(pageID: pageID, noteID: noteID)
    }
    #expect(try Data(contentsOf: drawingURL) == damagedData)
  }

  private func seedPersistentStore(
    schema: Schema,
    url: URL
  ) throws -> StoredIdentities {
    let configuration = ModelConfiguration(
      "Relaunch",
      schema: schema,
      url: url,
      cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let folder = Folder(name: "Mathematics")
    let note = Note(folderID: folder.id, title: "Limits")
    let page = Page(noteID: note.id, sortOrder: 0)
    container.mainContext.insert(folder)
    container.mainContext.insert(note)
    container.mainContext.insert(page)
    try container.mainContext.save()
    return StoredIdentities(folderID: folder.id, noteID: note.id, pageID: page.id)
  }
}

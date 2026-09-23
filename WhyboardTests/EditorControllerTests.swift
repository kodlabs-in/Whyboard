import Foundation
import PencilKit
import SwiftData
import Testing

@testable import Whyboard

@MainActor
struct EditorControllerTests {
  private enum MetadataFailure: Error {
    case rejected
  }

  @Test func scrollPositionTargetsThePageNearestTheViewportCenter() throws {
    let directories = try AppDirectories.makeForTesting()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let note = Note(folderID: UUID())
    let controller = EditorController(
      note: note,
      drawingRepository: DrawingRepository(directories: directories))
    let pageIDs = [UUID(), UUID(), UUID()]

    controller.updateActivePage(
      scrollOffset: 1_050,
      viewportHeight: 900,
      pageHeight: 1_000,
      orderedPageIDs: pageIDs)

    #expect(controller.activePageID == pageIDs[1])
  }

  @Test func insertReorderAndDeleteKeepStablePageIdentities() async throws {
    let container = try makeContainer()
    let context = container.mainContext
    let directories = try AppDirectories.makeForTesting()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let note = Note(folderID: UUID())
    let first = Page(noteID: note.id, sortOrder: 0)
    context.insert(note)
    context.insert(first)
    try context.save()
    let repository = DrawingRepository(directories: directories)
    let controller = EditorController(note: note, drawingRepository: repository)

    let secondID = controller.insertPage(
      relativeTo: first,
      after: true,
      pages: [first],
      context: context)
    var pages = try context.fetch(FetchDescriptor<Page>())
    let stableIDs = Set(pages.map(\.id))
    controller.movePages(from: [1], to: 0, pages: pages, context: context)
    pages = PageOrdering.ordered(try context.fetch(FetchDescriptor<Page>()))

    #expect(pages.map(\.id) == [secondID, first.id])
    #expect(Set(pages.map(\.id)) == stableIDs)
    #expect(pages.map(\.sortOrder) == [0, 1])

    guard let second = pages.first(where: { $0.id == secondID }) else {
      Issue.record("Inserted page was not found")
      return
    }
    await controller.deletePage(second, pages: pages, context: context)
    pages = try context.fetch(FetchDescriptor<Page>())

    #expect(pages.map(\.id) == [first.id])
    #expect(pages.first?.sortOrder == 0)
  }

  @Test func deletingTheOnlyPageIsRejected() async throws {
    let container = try makeContainer()
    let context = container.mainContext
    let directories = try AppDirectories.makeForTesting()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let note = Note(folderID: UUID())
    let page = Page(noteID: note.id, sortOrder: 0)
    context.insert(note)
    context.insert(page)
    let controller = EditorController(
      note: note,
      drawingRepository: DrawingRepository(directories: directories))

    await controller.deletePage(page, pages: [page], context: context)

    #expect(controller.errorMessage == "A note must always contain at least one page.")
    #expect(try context.fetchCount(FetchDescriptor<Page>()) == 1)
  }

  @Test func deletingTheActivePageFocusesItsNearestSurvivingNeighbor() async throws {
    let container = try makeContainer()
    let context = container.mainContext
    let directories = try AppDirectories.makeForTesting()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let note = Note(folderID: UUID())
    let pages = (0..<4).map { Page(noteID: note.id, sortOrder: $0) }
    context.insert(note)
    pages.forEach(context.insert)
    try context.save()
    let controller = EditorController(
      note: note,
      drawingRepository: DrawingRepository(directories: directories))

    controller.focus(pages[1].id)
    #expect(await controller.deletePage(pages[1], pages: pages, context: context))
    #expect(controller.activePageID == pages[2].id)

    let remaining = PageOrdering.ordered(try context.fetch(FetchDescriptor<Page>()))
    controller.focus(pages[3].id)
    #expect(await controller.deletePage(pages[3], pages: remaining, context: context))
    #expect(controller.activePageID == pages[2].id)
  }

  @Test func failedPageMetadataDeletionPreservesThePageAndItsPayload() async throws {
    let container = try makeContainer()
    let context = container.mainContext
    let directories = try AppDirectories.makeForTesting()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let note = Note(folderID: UUID())
    let first = Page(noteID: note.id, sortOrder: 0)
    let second = Page(noteID: note.id, sortOrder: 1)
    context.insert(note)
    context.insert(first)
    context.insert(second)
    try context.save()
    let repository = DrawingRepository(directories: directories)
    try await repository.save(PKDrawing(), pageID: second.id, noteID: note.id)
    let payloadURL = directories.drawings
      .appending(path: note.id.uuidString.lowercased(), directoryHint: .isDirectory)
      .appending(path: "\(second.id.uuidString.lowercased()).drawing")
    let controller = EditorController(note: note, drawingRepository: repository)
    controller.configure { throw MetadataFailure.rejected }

    let deleted = await controller.deletePage(
      second,
      pages: [first, second],
      context: context)

    #expect(!deleted)
    #expect(try context.fetchCount(FetchDescriptor<Page>()) == 2)
    #expect(FileManager.default.fileExists(atPath: payloadURL.path))
  }

  @Test func leavingTheLiveWindowReleasesDrawingAndElementSessionsTogether() async throws {
    let directories = try AppDirectories.makeForTesting()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let note = Note(folderID: UUID())
    let page = Page(noteID: note.id, sortOrder: 0)
    let controller = EditorController(
      note: note,
      drawingRepository: DrawingRepository(directories: directories))
    let drawingSession = controller.session(for: page, generatesPreview: false)
    let firstElementSession = controller.elementSession(for: page, canvasSize: CanonicalPage.size)
    await drawingSession.loadIfNeeded()
    controller.pageAppeared(page.id, orderedPageIDs: [page.id])

    controller.pageDisappeared(page.id, orderedPageIDs: [page.id])
    try await Task.sleep(for: .milliseconds(50))
    let replacementElementSession = controller.elementSession(
      for: page,
      canvasSize: CanonicalPage.size)

    #expect(replacementElementSession !== firstElementSession)
  }

  @Test func closingAfterASaveFailureKeepsARecoveryFlusherUntilRetrySucceeds() async throws {
    let directories = try AppDirectories.makeForTesting()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let note = Note(folderID: UUID())
    let page = Page(noteID: note.id, sortOrder: 0)
    let repository = DrawingRepository(directories: directories)
    let controller = EditorController(note: note, drawingRepository: repository)
    var metadataCanSave = false
    var metadataSaveAttempts = 0
    controller.configure {
      metadataSaveAttempts += 1
      if !metadataCanSave { throw MetadataFailure.rejected }
    }
    let session = controller.session(for: page, generatesPreview: false)
    await session.loadIfNeeded()
    session.drawingDidChange(PKDrawing())

    let closed = await controller.close()

    #expect(!closed)
    #expect(!(await repository.pendingSaves.flush(noteID: note.id)))
    metadataCanSave = true
    #expect(await repository.pendingSaves.flush(noteID: note.id))
    let attemptsAfterRecovery = metadataSaveAttempts
    #expect(await repository.pendingSaves.flush(noteID: note.id))
    #expect(metadataSaveAttempts == attemptsAfterRecovery)
  }

  private func makeContainer() throws -> ModelContainer {
    let schema = Schema([Folder.self, Note.self, Page.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
  }
}

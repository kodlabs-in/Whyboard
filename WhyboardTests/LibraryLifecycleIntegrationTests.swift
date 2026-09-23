import Foundation
import PencilKit
import SwiftData
import Testing

@testable import Whyboard

@MainActor
struct LibraryLifecycleIntegrationTests {
  @Test func failedNoteDeletionRollsBackMetadataAndPreservesStoredPayloads() async throws {
    let directories = try AppDirectories.makeForTesting()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let repository = DrawingRepository(directories: directories)
    let container = try makeContainer()
    let context = container.mainContext
    let root = Folder(name: "Unfiled Notes", isSystem: true)
    let note = Note(folderID: root.id, title: "Keep Me")
    let page = Page(noteID: note.id, sortOrder: 0)
    context.insert(root)
    context.insert(note)
    context.insert(page)
    try context.save()
    try await repository.save(PKDrawing(), pageID: page.id, noteID: note.id)
    let drawingURL = repository.drawingsDirectory
      .appending(path: note.id.uuidString.lowercased())
      .appending(path: "\(page.id.uuidString.lowercased()).drawing")

    let controller = LibraryController(saveAction: { _ in throw InjectedSaveError() })
    controller.confirmNoteDeletion(
      note,
      pages: [page],
      context: context,
      drawingRepository: repository)
    try #require(controller.confirmation).action()

    try await Task.sleep(for: .milliseconds(50))
    #expect(try context.fetch(FetchDescriptor<Note>()).map(\.id) == [note.id])
    #expect(try context.fetch(FetchDescriptor<Page>()).map(\.id) == [page.id])
    #expect(FileManager.default.fileExists(atPath: drawingURL.path))
    #expect(controller.errorMessage != nil)
  }

  @Test func deletingANoteRemovesMetadataAndStoredPayloadsButPreservesOtherNotes() async throws {
    let directories = try AppDirectories.makeForTesting()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let repository = DrawingRepository(directories: directories)
    let container = try makeContainer()
    let context = container.mainContext
    let root = Folder(name: "Unfiled Notes", isSystem: true)
    let deletedNote = Note(folderID: root.id, title: "Delete Me")
    let deletedPage = Page(noteID: deletedNote.id, sortOrder: 0)
    let survivingNote = Note(folderID: root.id, title: "Keep Me")
    let survivingPage = Page(noteID: survivingNote.id, sortOrder: 0)
    [root].forEach(context.insert)
    [deletedNote, survivingNote].forEach(context.insert)
    [deletedPage, survivingPage].forEach(context.insert)

    let attachmentSource = directories.recovery.appending(path: "attachment.png")
    try Data("attachment".utf8).write(to: attachmentSource)
    let attachmentFilename = try await repository.attachments.importFile(
      at: attachmentSource,
      noteID: deletedNote.id,
      pageID: deletedPage.id)
    deletedPage.workspaceElementsData = try WorkspaceElementCoding.encode([
      imageElement(filename: attachmentFilename)
    ])
    try await repository.save(PKDrawing(), pageID: deletedPage.id, noteID: deletedNote.id)
    try context.save()

    let drawingURL = repository.drawingsDirectory
      .appending(path: deletedNote.id.uuidString.lowercased())
      .appending(path: "\(deletedPage.id.uuidString.lowercased()).drawing")
    let attachmentURL = repository.attachments.fileURL(
      noteID: deletedNote.id,
      pageID: deletedPage.id,
      filename: attachmentFilename)
    #expect(FileManager.default.fileExists(atPath: drawingURL.path))
    #expect(FileManager.default.fileExists(atPath: attachmentURL.path))

    let controller = LibraryController()
    controller.confirmNoteDeletion(
      deletedNote,
      pages: [deletedPage, survivingPage],
      context: context,
      drawingRepository: repository)
    let confirmation = try #require(controller.confirmation)
    confirmation.action()

    await waitForRemoval(of: drawingURL, attachmentURL)

    let remainingNotes = try context.fetch(FetchDescriptor<Note>())
    let remainingPages = try context.fetch(FetchDescriptor<Page>())
    #expect(remainingNotes.map(\.id) == [survivingNote.id])
    #expect(remainingPages.map(\.id) == [survivingPage.id])
    #expect(!FileManager.default.fileExists(atPath: drawingURL.path))
    #expect(!FileManager.default.fileExists(atPath: attachmentURL.path))
  }

  @Test func deletingAFolderCascadesThroughNestedContentButPreservesSiblings() throws {
    let directories = try AppDirectories.makeForTesting()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let repository = DrawingRepository(directories: directories)
    let container = try makeContainer()
    let context = container.mainContext
    let root = Folder(name: "Unfiled Notes", isSystem: true)
    let parent = Folder(name: "Mathematics")
    let child = Folder(parentFolderID: parent.id, name: "Calculus")
    let sibling = Folder(name: "Physics")
    let deletedNote = Note(folderID: child.id, title: "Limits")
    let survivingNote = Note(folderID: sibling.id, title: "Motion")
    let deletedPage = Page(noteID: deletedNote.id, sortOrder: 0)
    let survivingPage = Page(noteID: survivingNote.id, sortOrder: 0)
    let deletedDocument = ImportedDocument(noteID: deletedNote.id, pageCount: 2)
    let survivingDocument = ImportedDocument(noteID: survivingNote.id, pageCount: 3)
    [root, parent, child, sibling].forEach(context.insert)
    [deletedNote, survivingNote].forEach(context.insert)
    [deletedPage, survivingPage].forEach(context.insert)
    [deletedDocument, survivingDocument].forEach(context.insert)
    try context.save()

    let controller = LibraryController()
    controller.confirmFolderDeletion(
      parent,
      mutationContext: LibraryMutationContext(
        folders: [root, parent, child, sibling],
        notes: [deletedNote, survivingNote],
        pages: [deletedPage, survivingPage],
        importedDocuments: [deletedDocument, survivingDocument],
        modelContext: context,
        drawingRepository: repository))
    let confirmation = try #require(controller.confirmation)
    #expect(confirmation.title == "Delete Mathematics?")
    confirmation.action()

    #expect(Set(try context.fetch(FetchDescriptor<Folder>()).map(\.id)) == [root.id, sibling.id])
    #expect(try context.fetch(FetchDescriptor<Note>()).map(\.id) == [survivingNote.id])
    #expect(try context.fetch(FetchDescriptor<Page>()).map(\.id) == [survivingPage.id])
    #expect(
      try context.fetch(FetchDescriptor<ImportedDocument>()).map(\.id)
        == [survivingDocument.id])
  }

  @Test func failedRecursiveFolderDeletionRollsBackEveryRecordAndPreservesPayloads() async throws {
    let directories = try AppDirectories.makeForTesting()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let repository = DrawingRepository(directories: directories)
    let container = try makeContainer()
    let context = container.mainContext
    let parent = Folder(name: "Mathematics")
    let child = Folder(parentFolderID: parent.id, name: "Calculus")
    let note = Note(folderID: child.id, title: "Limits")
    let page = Page(noteID: note.id, sortOrder: 0)
    let document = ImportedDocument(noteID: note.id, pageCount: 1)
    [parent, child].forEach(context.insert)
    context.insert(note)
    context.insert(page)
    context.insert(document)
    try context.save()
    try await repository.save(PKDrawing(), pageID: page.id, noteID: note.id)
    let drawingURL = repository.drawingsDirectory
      .appending(path: note.id.uuidString.lowercased())
      .appending(path: "\(page.id.uuidString.lowercased()).drawing")

    let controller = LibraryController(saveAction: { _ in throw InjectedSaveError() })
    controller.confirmFolderDeletion(
      parent,
      mutationContext: LibraryMutationContext(
        folders: [parent, child],
        notes: [note],
        pages: [page],
        importedDocuments: [document],
        modelContext: context,
        drawingRepository: repository))
    try #require(controller.confirmation).action()

    try await Task.sleep(for: .milliseconds(50))
    #expect(Set(try context.fetch(FetchDescriptor<Folder>()).map(\.id)) == [parent.id, child.id])
    #expect(try context.fetch(FetchDescriptor<Note>()).map(\.id) == [note.id])
    #expect(try context.fetch(FetchDescriptor<Page>()).map(\.id) == [page.id])
    #expect(try context.fetch(FetchDescriptor<ImportedDocument>()).map(\.id) == [document.id])
    #expect(FileManager.default.fileExists(atPath: drawingURL.path))
    #expect(controller.errorMessage != nil)
  }

  private func makeContainer() throws -> ModelContainer {
    let schema = Schema([Folder.self, Note.self, Page.self, ImportedDocument.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
  }

  private func imageElement(filename: String) -> WorkspaceElement {
    WorkspaceElement(
      kind: .image,
      frame: WorkspaceElementFrame(
        center: CGPoint(x: 200, y: 200),
        size: CGSize(width: 160, height: 120)),
      zIndex: 0,
      assetFilename: filename)
  }

  private func waitForRemoval(of urls: URL...) async {
    for _ in 0..<50 {
      guard urls.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
        return
      }
      try? await Task.sleep(for: .milliseconds(20))
    }
  }
}

private struct InjectedSaveError: LocalizedError {
  var errorDescription: String? { "Injected save failure" }
}

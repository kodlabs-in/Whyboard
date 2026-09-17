import Foundation
import SwiftData
import Testing

@testable import Whyboard

@MainActor
struct LibraryControllerTests {
  @Test func rootNoteCreationUsesUnfiledAndStartsWithOnePage() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let unfiled = Folder(name: "Unfiled Notes", isSystem: true)
    context.insert(unfiled)
    let controller = LibraryController()

    let createdNoteID = controller.createNote(in: .root, folders: [unfiled], context: context)

    let notes = try context.fetch(FetchDescriptor<Note>())
    let pages = try context.fetch(FetchDescriptor<Page>())
    #expect(notes.count == 1)
    #expect(notes.first?.folderID == unfiled.id)
    #expect(notes.first?.kind == .infinitePages)
    #expect(notes.first?.paperStyle == .white)
    #expect(pages.count == 1)
    #expect(pages.first?.noteID == notes.first?.id)
    #expect(createdNoteID == notes.first?.id)
  }

  @Test func createsAnInfiniteCanvasWithOneDrawingSurface() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let folder = Folder(name: "Ideas")
    context.insert(folder)
    let controller = LibraryController()

    let noteID = controller.createNote(
      in: .folder(folder.id),
      kind: .infiniteCanvas,
      folders: [folder],
      context: context)

    let notes = try context.fetch(FetchDescriptor<Note>())
    let pages = try context.fetch(FetchDescriptor<Page>())
    #expect(notes.first?.id == noteID)
    #expect(notes.first?.kind == .infiniteCanvas)
    #expect(pages.count == 1)
    #expect(pages.first?.noteID == noteID)
  }

  @Test func movingAndRenamingANotePreservesItsIdentity() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let source = Folder(name: "Source")
    let destination = Folder(name: "Destination")
    let note = Note(folderID: source.id, title: "Draft")
    [source, destination].forEach(context.insert)
    context.insert(note)
    let originalID = note.id
    let controller = LibraryController()

    controller.presentNoteMove(note, folders: [source, destination], context: context)
    controller.destinationPicker?.onSelect(destination)
    controller.presentNoteRename(note, context: context)
    controller.nameEditor?.onSave("Final")

    #expect(note.id == originalID)
    #expect(note.folderID == destination.id)
    #expect(note.title == "Final")
  }

  @Test func titleSearchIsLocalAndCaseInsensitive() {
    let folderID = UUID()
    let algebra = Note(folderID: folderID, title: "Linear Algebra")
    let physics = Note(folderID: folderID, title: "Physics")
    let controller = LibraryController()

    #expect(
      controller.filteredNotes([physics, algebra], matching: "ALGEBRA").map(\.id) == [
        algebra.id
      ])
  }

  @Test func browserShowsOnlyDirectFoldersAndNotes() {
    let rootStorage = Folder(name: "Unfiled Notes", isSystem: true)
    let mathematics = Folder(name: "Mathematics")
    let algebra = Folder(parentFolderID: mathematics.id, name: "Algebra")
    let nested = Folder(parentFolderID: algebra.id, name: "Linear Equations")
    let rootNote = Note(folderID: rootStorage.id, title: "Inbox")
    let mathNote = Note(folderID: mathematics.id, title: "Limits")
    let controller = LibraryController()
    let folders = [rootStorage, mathematics, algebra, nested]
    let notes = [rootNote, mathNote]

    #expect(controller.folders(in: .root, from: folders).map(\.id) == [mathematics.id])
    #expect(
      controller.folders(in: .folder(mathematics.id), from: folders).map(\.id) == [algebra.id])
    #expect(controller.notes(in: .root, from: notes, folders: folders).map(\.id) == [rootNote.id])
    #expect(
      controller.notes(in: .folder(mathematics.id), from: notes, folders: folders).map(\.id)
        == [mathNote.id])
  }

  @Test func notePaperStyleIsStoredIndependentlyFromTheDefault() {
    let note = Note(folderID: UUID(), paperStyle: .black)

    #expect(note.paperStyle == .black)
    #expect(note.paperStyleRawValue == NotePaperStyle.black.rawValue)
    #expect(note.paperStyle.resolved(defaultRawValue: NotePaperStyle.white.rawValue) == .black)
  }

  @Test func noteCreationSnapshotsTheSelectedDefaultPaperStyle() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let unfiled = Folder(name: "Unfiled Notes", isSystem: true)
    context.insert(unfiled)

    _ = LibraryController().createNote(
      in: .root,
      paperStyle: .black,
      folders: [unfiled],
      context: context)

    let note = try #require(context.fetch(FetchDescriptor<Note>()).first)
    #expect(note.paperStyle == .black)
    #expect(note.paperStyleRawValue == NotePaperStyle.black.rawValue)
  }

  @Test func missingOrUnknownNoteKindMigratesToInfinitePages() {
    let note = Note(folderID: UUID(), kind: .infiniteCanvas)
    #expect(note.kind == .infiniteCanvas)

    note.noteKindRawValue = nil
    #expect(note.kind == .infinitePages)

    note.noteKindRawValue = "future-note-kind"
    #expect(note.kind == .infinitePages)
  }

  private func makeContainer() throws -> ModelContainer {
    let schema = Schema([Folder.self, Note.self, Page.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
  }
}

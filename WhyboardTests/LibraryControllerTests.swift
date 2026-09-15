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

    controller.createNote(folders: [unfiled], context: context)

    let notes = try context.fetch(FetchDescriptor<Note>())
    let pages = try context.fetch(FetchDescriptor<Page>())
    #expect(notes.count == 1)
    #expect(notes.first?.folderID == unfiled.id)
    #expect(pages.count == 1)
    #expect(pages.first?.noteID == notes.first?.id)
    #expect(controller.selectedNoteID == notes.first?.id)
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
    controller.searchText = "ALGEBRA"

    #expect(controller.visibleNotes(from: [physics, algebra]).map(\.id) == [algebra.id])
  }

  private func makeContainer() throws -> ModelContainer {
    let schema = Schema([Folder.self, Note.self, Page.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
  }
}

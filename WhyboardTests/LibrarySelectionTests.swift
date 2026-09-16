import Foundation
import SwiftData
import Testing

@testable import Whyboard

@MainActor
struct LibrarySelectionTests {
  @Test func mixedSelectionExpandsDescendantsAndDeletionImpact() throws {
    let parent = Folder(name: "Parent")
    let child = Folder(parentFolderID: parent.id, name: "Child")
    let root = Folder(name: "Library", isSystem: true)
    let nestedNote = Note(folderID: child.id, title: "Nested")
    let rootNote = Note(folderID: root.id, title: "Root")
    let nestedPage = Page(noteID: nestedNote.id, sortOrder: 0)
    nestedPage.workspaceElementsData = try WorkspaceElementCoding.encode([
      imageElement(filename: "one.png"),
      imageElement(filename: "two.png"),
    ])
    let rootPage = Page(noteID: rootNote.id, sortOrder: 0)

    let plan = LibrarySelectionPlan(
      selection: [.folder(parent.id), .note(rootNote.id)],
      folders: [root, parent, child],
      notes: [nestedNote, rootNote],
      pages: [nestedPage, rootPage])

    #expect(plan.affectedFolderIDs == [parent.id, child.id])
    #expect(plan.affectedNoteIDs == [nestedNote.id, rootNote.id])
    #expect(plan.affectedPageIDs == [nestedPage.id, rootPage.id])
    #expect(
      plan.impact
        == LibrarySelectionImpact(
          folderCount: 2,
          noteCount: 2,
          pageCount: 2,
          attachmentCount: 2))
  }

  @Test func movingNestedSelectionMovesOnlyTopLevelFolder() {
    let parent = Folder(name: "Parent")
    let child = Folder(parentFolderID: parent.id, name: "Child")
    let note = Note(folderID: child.id)

    let plan = LibrarySelectionPlan(
      selection: [.folder(parent.id), .folder(child.id), .note(note.id)],
      folders: [parent, child],
      notes: [note],
      pages: [])

    #expect(plan.movedFolderIDs == [parent.id])
    #expect(plan.movedNoteIDs.isEmpty)
  }

  @Test func everySelectedFolderAndDescendantIsAnInvalidDestination() {
    let parent = Folder(name: "Parent")
    let child = Folder(parentFolderID: parent.id, name: "Child")
    let sibling = Folder(name: "Sibling")
    let plan = LibrarySelectionPlan(
      selection: [.folder(parent.id)],
      folders: [parent, child, sibling],
      notes: [],
      pages: [])

    #expect(!plan.canMove(to: parent.id))
    #expect(!plan.canMove(to: child.id))
    #expect(plan.canMove(to: sibling.id))
    #expect(plan.canMove(to: nil))
  }

  @Test func invalidMoveDoesNotPartiallyMutateSelection() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let root = Folder(name: "Library", isSystem: true)
    let parent = Folder(name: "Parent")
    let child = Folder(parentFolderID: parent.id, name: "Child")
    let note = Note(folderID: root.id)
    [root, parent, child].forEach(context.insert)
    context.insert(note)
    try context.save()
    let plan = LibrarySelectionPlan(
      selection: [.folder(parent.id), .note(note.id)],
      folders: [root, parent, child],
      notes: [note],
      pages: [])

    #expect(throws: BulkLibraryError.invalidDestination) {
      try BulkLibraryService().move(
        plan: plan,
        to: child,
        folders: [root, parent, child],
        notes: [note],
        context: context)
    }
    #expect(parent.parentFolderID == nil)
    #expect(note.folderID == root.id)
  }

  private func imageElement(filename: String) -> WorkspaceElement {
    WorkspaceElement(
      kind: .image,
      frame: WorkspaceElementFrame(
        center: CGPoint(x: 100, y: 100),
        size: CGSize(width: 80, height: 60)),
      zIndex: 0,
      assetFilename: filename)
  }

  private func makeContainer() throws -> ModelContainer {
    let schema = Schema([Folder.self, Note.self, Page.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
  }
}

import Foundation
import SwiftData

extension LibraryController {
  @discardableResult
  func createNote(
    in location: LibraryLocation,
    folders: [Folder],
    context: ModelContext
  ) -> UUID? {
    guard let folderID = storageFolderID(for: location, folders: folders) else {
      errorMessage = "Whyboard couldn't find the current folder."
      return nil
    }

    let note = Note(folderID: folderID)
    context.insert(note)
    context.insert(Page(noteID: note.id, sortOrder: 0))
    save(context)
    return note.id
  }

  func presentNoteRename(_ note: Note, context: ModelContext) {
    nameEditor = NameEditorRequest(
      title: "Rename Note",
      prompt: "Note title",
      initialName: note.title,
      systemImage: "note.text"
    ) { [weak self] title in
      note.title = title
      note.updatedAt = Date()
      self?.save(context)
    }
  }

  func presentNoteMove(_ note: Note, folders: [Folder], context: ModelContext) {
    let rootFolderID = rootFolder(in: folders)?.id
    destinationPicker = DestinationPickerRequest(
      title: "Move \(note.title)",
      destinations: noteDestinations(from: folders),
      currentFolderID: note.folderID == rootFolderID ? nil : note.folderID
    ) { [weak self] destination in
      guard let self else { return }
      guard let folderID = destination?.id ?? rootFolderID else {
        errorMessage = "Whyboard couldn't find the Library."
        return
      }
      note.folderID = folderID
      note.updatedAt = Date()
      save(context)
    }
  }

  func confirmNoteDeletion(
    _ note: Note,
    pages: [Page],
    context: ModelContext,
    drawingRepository: DrawingRepository
  ) {
    confirmation = ConfirmationRequest(
      title: "Delete \(note.title)?",
      message: "This permanently deletes every page and drawing in this note.",
      actionTitle: "Delete Note"
    ) { [weak self] in
      self?.deleteNote(
        note,
        pages: pages,
        context: context,
        drawingRepository: drawingRepository)
    }
  }

  private func noteDestinations(from folders: [Folder]) -> [FolderDestination] {
    FolderHierarchy.destinations(from: folders, includeRoot: true)
  }

  private func deleteNote(
    _ note: Note,
    pages: [Page],
    context: ModelContext,
    drawingRepository: DrawingRepository
  ) {
    pages.filter { $0.noteID == note.id }.forEach(context.delete)
    context.delete(note)
    save(context)

    let noteID = note.id
    Task { await drawingRepository.deleteNote(noteID: noteID) }
  }
}

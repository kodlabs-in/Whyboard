import Foundation
import SwiftData

extension LibraryController {
  func createNote(folders: [Folder], context: ModelContext) {
    guard let folderID = noteDestinationFolderID(in: folders) else {
      errorMessage = "The Unfiled Notes folder is unavailable."
      return
    }

    let note = Note(folderID: folderID)
    context.insert(note)
    context.insert(Page(noteID: note.id, sortOrder: 0))
    save(context)
    selectedNoteID = note.id
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
    destinationPicker = DestinationPickerRequest(
      title: "Move \(note.title)",
      destinations: noteDestinations(from: folders),
      currentFolderID: note.folderID
    ) { [weak self] destination in
      guard let self, let destination else { return }
      note.folderID = destination.id
      note.updatedAt = Date()
      save(context)
      location = .folder(destination.id)
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

  private func noteDestinationFolderID(in folders: [Folder]) -> UUID? {
    switch location ?? .all {
    case .all:
      folders.first(where: \.isSystem)?.id
    case .folder(let folderID):
      folderID
    }
  }

  private func noteDestinations(from folders: [Folder]) -> [FolderDestination] {
    let unfiled =
      folders.first(where: \.isSystem).map {
        [FolderDestination(folder: $0, depth: 0)]
      } ?? []
    return unfiled + FolderHierarchy.destinations(from: folders, includeRoot: false)
  }

  private func deleteNote(
    _ note: Note,
    pages: [Page],
    context: ModelContext,
    drawingRepository: DrawingRepository
  ) {
    pages.filter { $0.noteID == note.id }.forEach(context.delete)
    context.delete(note)
    if selectedNoteID == note.id {
      selectedNoteID = nil
    }
    save(context)

    let noteID = note.id
    Task { await drawingRepository.deleteNote(noteID: noteID) }
  }
}

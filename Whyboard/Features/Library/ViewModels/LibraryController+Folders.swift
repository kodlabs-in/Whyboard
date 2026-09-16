import Foundation
import SwiftData

extension LibraryController {
  func presentNewFolder(
    in location: LibraryLocation,
    folders: [Folder],
    context: ModelContext
  ) {
    let parentID = parentFolderID(for: location, folders: folders)
    nameEditor = NameEditorRequest(
      title: "New Folder",
      prompt: "Folder name",
      initialName: "",
      systemImage: "folder.badge.plus"
    ) { [weak self] name in
      self?.createFolder(named: name, parentID: parentID, folders: folders, context: context)
    }
  }

  func presentFolderRename(_ folder: Folder, context: ModelContext) {
    nameEditor = NameEditorRequest(
      title: "Rename Folder",
      prompt: "Folder name",
      initialName: folder.name,
      systemImage: "folder"
    ) { [weak self] name in
      folder.name = name
      folder.updatedAt = Date()
      self?.save(context)
    }
  }

  func presentFolderMove(_ folder: Folder, folders: [Folder], context: ModelContext) {
    let excluded = FolderHierarchy.descendantIDs(of: folder.id, in: folders).union([folder.id])
    destinationPicker = DestinationPickerRequest(
      title: "Move \(folder.name)",
      destinations: FolderHierarchy.destinations(
        from: folders,
        excluding: excluded,
        includeRoot: true),
      currentFolderID: folder.parentFolderID
    ) { [weak self] destination in
      self?.move(folder, to: destination, folders: folders, context: context)
    }
  }

  func confirmFolderDeletion(
    _ folder: Folder,
    mutationContext: LibraryMutationContext
  ) {
    confirmation = ConfirmationRequest(
      title: "Delete \(folder.name)?",
      message: "This permanently deletes the folder, its subfolders, and every note inside.",
      actionTitle: "Delete Folder"
    ) { [weak self] in
      self?.deleteFolder(
        folder,
        mutationContext: mutationContext)
    }
  }

  private func parentFolderID(for location: LibraryLocation, folders: [Folder]) -> UUID? {
    guard case .folder(let folderID) = location else { return nil }
    return folders.first { $0.id == folderID && !$0.isSystem }?.id
  }

  private func createFolder(
    named name: String,
    parentID: UUID?,
    folders: [Folder],
    context: ModelContext
  ) {
    let siblings = folders.filter { $0.parentFolderID == parentID && !$0.isSystem }
    context.insert(
      Folder(parentFolderID: parentID, name: name, sortOrder: siblings.count))
    save(context)
  }

  private func move(
    _ folder: Folder,
    to destination: Folder?,
    folders: [Folder],
    context: ModelContext
  ) {
    guard FolderHierarchy.canMove(folder.id, to: destination?.id, in: folders) else { return }
    folder.parentFolderID = destination?.id
    folder.updatedAt = Date()
    save(context)
  }

  private func deleteFolder(
    _ folder: Folder,
    mutationContext: LibraryMutationContext
  ) {
    let folderIDs = FolderHierarchy.descendantIDs(
      of: folder.id,
      in: mutationContext.folders
    ).union([folder.id])
    let deletedNotes = mutationContext.notes.filter { folderIDs.contains($0.folderID) }
    let deletedNoteIDs = Set(deletedNotes.map(\.id))

    mutationContext.pages
      .filter { deletedNoteIDs.contains($0.noteID) }
      .forEach(mutationContext.modelContext.delete)
    mutationContext.importedDocuments
      .filter { deletedNoteIDs.contains($0.noteID) }
      .forEach(mutationContext.modelContext.delete)
    deletedNotes.forEach(mutationContext.modelContext.delete)
    mutationContext.folders
      .filter { folderIDs.contains($0.id) }
      .forEach(mutationContext.modelContext.delete)
    save(mutationContext.modelContext)

    let drawingRepository = mutationContext.drawingRepository
    Task {
      for noteID in deletedNoteIDs {
        await drawingRepository.deleteNote(noteID: noteID)
      }
    }
  }
}

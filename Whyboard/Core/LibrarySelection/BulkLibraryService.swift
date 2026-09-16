import Foundation
import SwiftData

enum BulkLibraryError: LocalizedError {
  case emptySelection
  case invalidDestination
  case missingLibraryRoot
  case saveFailed

  var errorDescription: String? {
    switch self {
    case .emptySelection:
      "Choose at least one note or folder."
    case .invalidDestination:
      "A folder cannot be moved into itself or one of its subfolders."
    case .missingLibraryRoot:
      "Whyboard couldn't find the Library destination."
    case .saveFailed:
      "Whyboard couldn't save the library change. Nothing was moved or deleted."
    }
  }
}

@MainActor
struct BulkLibraryService {
  func move(
    plan: LibrarySelectionPlan,
    to destination: Folder?,
    folders: [Folder],
    notes: [Note],
    context: ModelContext
  ) throws {
    guard !plan.isEmpty else { throw BulkLibraryError.emptySelection }
    guard plan.canMove(to: destination?.id) else { throw BulkLibraryError.invalidDestination }
    let rootID = try storageFolderID(destination: destination, folders: folders)
    applyFolderMove(plan: plan, destination: destination, folders: folders)
    applyNoteMove(plan: plan, destinationID: rootID, notes: notes)
    try save(context)
  }

  func delete(
    plan: LibrarySelectionPlan,
    mutationContext: LibraryMutationContext
  ) throws {
    guard !plan.isEmpty else { throw BulkLibraryError.emptySelection }
    mutationContext.pages.lazy
      .filter { plan.affectedPageIDs.contains($0.id) }
      .forEach(mutationContext.modelContext.delete)
    mutationContext.importedDocuments.lazy
      .filter { plan.affectedNoteIDs.contains($0.noteID) }
      .forEach(mutationContext.modelContext.delete)
    mutationContext.notes.lazy
      .filter { plan.affectedNoteIDs.contains($0.id) }
      .forEach(mutationContext.modelContext.delete)
    mutationContext.folders.lazy
      .filter { plan.affectedFolderIDs.contains($0.id) }
      .forEach(mutationContext.modelContext.delete)
    try save(mutationContext.modelContext)
    cleanup(
      noteIDs: plan.affectedNoteIDs,
      drawingRepository: mutationContext.drawingRepository)
  }

  private func storageFolderID(destination: Folder?, folders: [Folder]) throws -> UUID {
    if let destination { return destination.id }
    guard let rootID = folders.first(where: \.isSystem)?.id else {
      throw BulkLibraryError.missingLibraryRoot
    }
    return rootID
  }

  private func applyFolderMove(
    plan: LibrarySelectionPlan,
    destination: Folder?,
    folders: [Folder]
  ) {
    let now = Date()
    for folder in folders where plan.movedFolderIDs.contains(folder.id) {
      folder.parentFolderID = destination?.id
      folder.updatedAt = now
    }
  }

  private func applyNoteMove(
    plan: LibrarySelectionPlan,
    destinationID: UUID,
    notes: [Note]
  ) {
    let now = Date()
    for note in notes where plan.movedNoteIDs.contains(note.id) {
      note.folderID = destinationID
      note.updatedAt = now
    }
  }

  private func save(_ context: ModelContext) throws {
    do {
      try context.save()
    } catch {
      context.rollback()
      throw BulkLibraryError.saveFailed
    }
  }

  private func cleanup(noteIDs: Set<UUID>, drawingRepository: DrawingRepository) {
    Task.detached(priority: .utility) {
      for noteID in noteIDs {
        await drawingRepository.deleteNote(noteID: noteID)
      }
    }
  }
}

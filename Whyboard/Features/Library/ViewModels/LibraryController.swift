import Observation
import SwiftData
import SwiftUI

@Observable
final class LibraryController {
  var nameEditor: NameEditorRequest?
  var destinationPicker: DestinationPickerRequest?
  var confirmation: ConfirmationRequest?
  var errorMessage: String?

  var confirmationIsPresented: Bool {
    get { confirmation != nil }
    set { if !newValue { confirmation = nil } }
  }

  var errorIsPresented: Bool {
    get { errorMessage != nil }
    set { if !newValue { errorMessage = nil } }
  }

  func folders(in location: LibraryLocation, from folders: [Folder]) -> [Folder] {
    let parentID: UUID?
    switch location {
    case .root:
      parentID = nil
    case .folder(let folderID):
      parentID = folderID
    }

    return folders.filter { !$0.isSystem && $0.parentFolderID == parentID }
  }

  func notes(
    in location: LibraryLocation,
    from notes: [Note],
    folders: [Folder]
  ) -> [Note] {
    guard let folderID = storageFolderID(for: location, folders: folders) else { return [] }
    return notes.filter { $0.folderID == folderID }
  }

  func locationTitle(_ location: LibraryLocation, folders: [Folder]) -> String {
    switch location {
    case .root:
      "Whyboard"
    case .folder(let folderID):
      folders.first { $0.id == folderID }?.name ?? "Folder"
    }
  }

  func filteredNotes(_ notes: [Note], matching searchText: String) -> [Note] {
    guard !searchText.isEmpty else { return notes }
    return notes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
  }

  func rootFolder(in folders: [Folder]) -> Folder? {
    folders.first(where: \.isSystem)
  }

  func storageFolderID(for location: LibraryLocation, folders: [Folder]) -> UUID? {
    switch location {
    case .root:
      rootFolder(in: folders)?.id
    case .folder(let folderID):
      folderID
    }
  }

  func save(_ context: ModelContext) {
    do {
      try context.save()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

import Observation
import SwiftData
import SwiftUI

@Observable
final class LibraryController {
  typealias SaveAction = @MainActor (ModelContext) throws -> Void

  var nameEditor: NameEditorRequest?
  var destinationPicker: DestinationPickerRequest?
  var confirmation: ConfirmationRequest?
  var errorMessage: String?

  @ObservationIgnored private let saveAction: SaveAction

  init(saveAction: @escaping SaveAction = { try $0.save() }) {
    self.saveAction = saveAction
  }

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

  @discardableResult
  func save(_ context: ModelContext) -> Bool {
    do {
      try saveAction(context)
      return true
    } catch {
      context.rollback()
      errorMessage = error.localizedDescription
      return false
    }
  }
}

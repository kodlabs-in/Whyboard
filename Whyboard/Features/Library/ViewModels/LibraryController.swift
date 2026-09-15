import Observation
import SwiftData
import SwiftUI

@Observable
final class LibraryController {
  var location: LibraryLocation? = .all
  var selectedNoteID: UUID?
  var searchText = ""
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

  func selectedNote(in notes: [Note]) -> Note? {
    notes.first { $0.id == selectedNoteID }
  }

  func visibleNotes(from notes: [Note]) -> [Note] {
    notes.filter(matchesLocation).filter(matchesSearch)
  }

  func locationTitle(folders: [Folder]) -> String {
    switch location ?? .all {
    case .all:
      "All Notes"
    case .folder(let folderID):
      folders.first { $0.id == folderID }?.name ?? "Notes"
    }
  }

  func restoreLastOpenedNote(idString: String, notes: [Note]) {
    guard let id = UUID(uuidString: idString) else { return }
    selectedNoteID = notes.first { $0.id == id }?.id
  }

  func save(_ context: ModelContext) {
    do {
      try context.save()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func matchesLocation(_ note: Note) -> Bool {
    switch location ?? .all {
    case .all:
      true
    case .folder(let folderID):
      note.folderID == folderID
    }
  }

  private func matchesSearch(_ note: Note) -> Bool {
    searchText.isEmpty || note.title.localizedCaseInsensitiveContains(searchText)
  }
}

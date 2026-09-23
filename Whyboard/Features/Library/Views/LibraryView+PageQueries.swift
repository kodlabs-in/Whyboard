import Foundation
import SwiftData

enum LibraryRoute: Hashable {
  case folder(UUID)
  case note(UUID)
  case settings
}

extension LibraryView {
  func fetchPages(noteIDs: Set<UUID>? = nil) throws -> [Page] {
    guard let noteIDs else {
      return try modelContext.fetch(
        FetchDescriptor<Page>(sortBy: [SortDescriptor(\Page.sortOrder)]))
    }
    let requestedIDs = Array(noteIDs)
    let predicate = #Predicate<Page> { requestedIDs.contains($0.noteID) }
    return try modelContext.fetch(
      FetchDescriptor<Page>(predicate: predicate, sortBy: [SortDescriptor(\Page.sortOrder)]))
  }
}

struct LibraryPageSummaryRequest: Hashable {
  private struct NoteRevision: Hashable {
    let noteID: UUID
    let updatedAt: Date
  }

  private let noteRevisions: [NoteRevision]

  init(notes: [Note]) {
    noteRevisions =
      notes
      .map { NoteRevision(noteID: $0.id, updatedAt: $0.updatedAt) }
      .sorted { $0.noteID.uuidString < $1.noteID.uuidString }
  }
}

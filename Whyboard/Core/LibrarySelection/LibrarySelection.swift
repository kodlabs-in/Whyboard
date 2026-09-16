import Foundation

enum LibrarySelectionItem: Hashable, Sendable {
  case folder(UUID)
  case note(UUID)
}

struct LibrarySelectionImpact: Equatable, Sendable {
  let folderCount: Int
  let noteCount: Int
  let pageCount: Int
  let attachmentCount: Int

  var summary: String {
    "This permanently deletes \(folderCount) folders, \(noteCount) notes, "
      + "\(pageCount) pages, and \(attachmentCount) attachments."
  }
}

struct LibrarySelectionPlan {
  let selectedFolderIDs: Set<UUID>
  let selectedNoteIDs: Set<UUID>
  let movedFolderIDs: Set<UUID>
  let movedNoteIDs: Set<UUID>
  let affectedFolderIDs: Set<UUID>
  let affectedNoteIDs: Set<UUID>
  let affectedPageIDs: Set<UUID>
  let excludedDestinationIDs: Set<UUID>
  let impact: LibrarySelectionImpact

  init(
    selection: Set<LibrarySelectionItem>,
    folders: [Folder],
    notes: [Note],
    pages: [Page]
  ) {
    let folderIDs = Self.folderIDs(in: selection, folders: folders)
    let noteIDs = Self.noteIDs(in: selection, notes: notes)
    let affectedFolders = Self.expandedFolderIDs(folderIDs, folders: folders)
    let affectedNotes = Self.expandedNoteIDs(
      noteIDs,
      affectedFolderIDs: affectedFolders,
      notes: notes)
    let affectedPages = pages.filter { affectedNotes.contains($0.noteID) }

    selectedFolderIDs = folderIDs
    selectedNoteIDs = noteIDs
    movedFolderIDs = Self.topLevelFolderIDs(folderIDs, folders: folders)
    movedNoteIDs = Set(
      notes.lazy
        .filter { noteIDs.contains($0.id) && !affectedFolders.contains($0.folderID) }
        .map(\.id))
    affectedFolderIDs = affectedFolders
    affectedNoteIDs = affectedNotes
    affectedPageIDs = Set(affectedPages.map(\.id))
    excludedDestinationIDs = affectedFolders
    impact = LibrarySelectionImpact(
      folderCount: affectedFolders.count,
      noteCount: affectedNotes.count,
      pageCount: affectedPages.count,
      attachmentCount: Self.attachmentCount(in: affectedPages))
  }

  var isEmpty: Bool {
    selectedFolderIDs.isEmpty && selectedNoteIDs.isEmpty
  }

  func canMove(to destinationFolderID: UUID?) -> Bool {
    guard let destinationFolderID else { return true }
    return !excludedDestinationIDs.contains(destinationFolderID)
  }

  private static func folderIDs(
    in selection: Set<LibrarySelectionItem>,
    folders: [Folder]
  ) -> Set<UUID> {
    let available = Set(folders.lazy.filter { !$0.isSystem }.map(\.id))
    return Set(
      selection.compactMap { item in
        guard case .folder(let id) = item, available.contains(id) else { return nil }
        return id
      })
  }

  private static func noteIDs(
    in selection: Set<LibrarySelectionItem>,
    notes: [Note]
  ) -> Set<UUID> {
    let available = Set(notes.map(\.id))
    return Set(
      selection.compactMap { item in
        guard case .note(let id) = item, available.contains(id) else { return nil }
        return id
      })
  }

  private static func expandedFolderIDs(
    _ selectedIDs: Set<UUID>,
    folders: [Folder]
  ) -> Set<UUID> {
    selectedIDs.reduce(into: selectedIDs) { result, folderID in
      result.formUnion(FolderHierarchy.descendantIDs(of: folderID, in: folders))
    }
  }

  private static func expandedNoteIDs(
    _ selectedIDs: Set<UUID>,
    affectedFolderIDs: Set<UUID>,
    notes: [Note]
  ) -> Set<UUID> {
    selectedIDs.union(notes.lazy.filter { affectedFolderIDs.contains($0.folderID) }.map(\.id))
  }

  private static func topLevelFolderIDs(
    _ selectedIDs: Set<UUID>,
    folders: [Folder]
  ) -> Set<UUID> {
    let parentByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0.parentFolderID) })
    return Set(selectedIDs.filter { !hasSelectedAncestor($0, selectedIDs, parentByID) })
  }

  private static func hasSelectedAncestor(
    _ folderID: UUID,
    _ selectedIDs: Set<UUID>,
    _ parentByID: [UUID: UUID?]
  ) -> Bool {
    var parentID = parentByID[folderID] ?? nil
    var visited: Set<UUID> = []
    while let current = parentID, visited.insert(current).inserted {
      if selectedIDs.contains(current) { return true }
      parentID = parentByID[current] ?? nil
    }
    return false
  }

  private static func attachmentCount(in pages: [Page]) -> Int {
    pages.reduce(0) { count, page in
      count
        + Set(
          WorkspaceElementCoding.decode(page.workspaceElementsData).compactMap(\.assetFilename)
        ).count
    }
  }
}

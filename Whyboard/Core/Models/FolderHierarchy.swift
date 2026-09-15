import Foundation

struct FolderTreeNode: Identifiable {
  let folder: Folder
  let children: [FolderTreeNode]?

  var id: UUID { folder.id }
}

struct FolderDestination: Identifiable {
  let folder: Folder?
  let depth: Int

  var id: String { folder?.id.uuidString ?? "library-root" }
}

enum FolderHierarchy {
  static func tree(from folders: [Folder]) -> [FolderTreeNode] {
    let userFolders = folders.filter { !$0.isSystem }
    return sorted(userFolders.filter { $0.parentFolderID == nil }).map {
      node(for: $0, in: userFolders, ancestors: [])
    }
  }

  static func descendantIDs(of folderID: UUID, in folders: [Folder]) -> Set<UUID> {
    var descendants: Set<UUID> = []
    var pending = [folderID]

    while let parentID = pending.popLast() {
      let childIDs = folders.filter { $0.parentFolderID == parentID }.map(\.id)
      for childID in childIDs where descendants.insert(childID).inserted {
        pending.append(childID)
      }
    }

    return descendants
  }

  static func canMove(_ folderID: UUID, to parentID: UUID?, in folders: [Folder]) -> Bool {
    guard parentID != folderID else { return false }
    guard let parentID else { return true }
    return !descendantIDs(of: folderID, in: folders).contains(parentID)
  }

  static func destinations(
    from folders: [Folder],
    excluding excludedIDs: Set<UUID> = [],
    includeRoot: Bool
  ) -> [FolderDestination] {
    var result = includeRoot ? [FolderDestination(folder: nil, depth: 0)] : []
    appendDestinations(
      nodes: tree(from: folders),
      depth: 0,
      excludedIDs: excludedIDs,
      to: &result)
    return result
  }

  private static func node(
    for folder: Folder,
    in folders: [Folder],
    ancestors: Set<UUID>
  ) -> FolderTreeNode {
    guard !ancestors.contains(folder.id) else {
      return FolderTreeNode(folder: folder, children: nil)
    }

    let nextAncestors = ancestors.union([folder.id])
    let children = sorted(folders.filter { $0.parentFolderID == folder.id }).map {
      node(for: $0, in: folders, ancestors: nextAncestors)
    }
    return FolderTreeNode(folder: folder, children: children.isEmpty ? nil : children)
  }

  private static func sorted(_ folders: [Folder]) -> [Folder] {
    folders.sorted {
      if $0.sortOrder == $1.sortOrder {
        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
      }
      return $0.sortOrder < $1.sortOrder
    }
  }

  private static func appendDestinations(
    nodes: [FolderTreeNode],
    depth: Int,
    excludedIDs: Set<UUID>,
    to result: inout [FolderDestination]
  ) {
    for node in nodes where !excludedIDs.contains(node.id) {
      result.append(FolderDestination(folder: node.folder, depth: depth))
      appendDestinations(
        nodes: node.children ?? [],
        depth: depth + 1,
        excludedIDs: excludedIDs,
        to: &result)
    }
  }
}

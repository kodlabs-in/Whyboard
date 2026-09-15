import Foundation
import Testing

@testable import Whyboard

@MainActor
struct FolderHierarchyTests {
  @Test func buildsSortedNestedTreeAndIgnoresSystemFolders() {
    let root = Folder(name: "Math", sortOrder: 1)
    let earlierRoot = Folder(name: "Art", sortOrder: 0)
    let child = Folder(parentFolderID: root.id, name: "Algebra")
    let system = Folder(name: "Unfiled Notes", isSystem: true)

    let tree = FolderHierarchy.tree(from: [child, system, root, earlierRoot])

    #expect(tree.map(\.folder.id) == [earlierRoot.id, root.id])
    #expect(tree[1].children?.map(\.folder.id) == [child.id])
  }

  @Test func findsEveryDescendantAndPreventsFolderCycles() {
    let root = Folder(name: "University")
    let child = Folder(parentFolderID: root.id, name: "Semester One")
    let grandchild = Folder(parentFolderID: child.id, name: "Physics")
    let folders = [root, child, grandchild]

    #expect(FolderHierarchy.descendantIDs(of: root.id, in: folders) == [child.id, grandchild.id])
    #expect(!FolderHierarchy.canMove(root.id, to: root.id, in: folders))
    #expect(!FolderHierarchy.canMove(root.id, to: grandchild.id, in: folders))
    #expect(FolderHierarchy.canMove(grandchild.id, to: root.id, in: folders))
    #expect(FolderHierarchy.canMove(root.id, to: nil, in: folders))
  }

  @Test func destinationListExcludesAnEntireMovingSubtree() {
    let root = Folder(name: "Root")
    let child = Folder(parentFolderID: root.id, name: "Child")
    let peer = Folder(name: "Peer")
    let excluded = FolderHierarchy.descendantIDs(of: root.id, in: [root, child, peer])
      .union([root.id])

    let destinations = FolderHierarchy.destinations(
      from: [root, child, peer],
      excluding: excluded,
      includeRoot: true)

    #expect(destinations.compactMap(\.folder?.id) == [peer.id])
    #expect(destinations.first?.folder == nil)
  }
}

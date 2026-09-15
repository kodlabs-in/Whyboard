import SwiftUI

struct FolderSidebar: View {
  let folders: [Folder]
  @Binding var selection: LibraryLocation?
  let onCreateFolder: () -> Void
  let onRenameFolder: (Folder) -> Void
  let onMoveFolder: (Folder) -> Void
  let onDeleteFolder: (Folder) -> Void

  private var unfiledFolder: Folder? {
    folders.first(where: \.isSystem)
  }

  private var folderTree: [FolderTreeNode] {
    FolderHierarchy.tree(from: folders)
  }

  var body: some View {
    List(selection: $selection) {
      Section {
        Label("All Notes", systemImage: "square.grid.2x2")
          .tag(LibraryLocation.all)

        if let unfiledFolder {
          Label(unfiledFolder.name, systemImage: "tray.full")
            .tag(LibraryLocation.folder(unfiledFolder.id))
        }
      }

      Section("Folders") {
        if folderTree.isEmpty {
          Text("Create a folder for your first subject.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else {
          OutlineGroup(folderTree, children: \.children) { node in
            folderRow(node.folder)
          }
        }
      }
    }
    .navigationTitle("Whyboard")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("New Folder", systemImage: "folder.badge.plus", action: onCreateFolder)
          .accessibilityHint("Creates a folder in the selected location")
      }
    }
  }

  private func folderRow(_ folder: Folder) -> some View {
    Label(folder.name, systemImage: "folder")
      .tag(LibraryLocation.folder(folder.id))
      .contextMenu {
        Button("Rename", systemImage: "pencil") { onRenameFolder(folder) }
        Button("Move", systemImage: "folder") { onMoveFolder(folder) }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
          onDeleteFolder(folder)
        }
      }
  }
}

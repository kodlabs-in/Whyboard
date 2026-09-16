import SwiftUI

struct LibraryBrowserView: View {
  let title: String
  let folders: [Folder]
  let notes: [Note]
  let pageCounts: [UUID: Int]
  let coverPages: [UUID: Page]
  let drawingRepository: DrawingRepository
  let showsSettings: Bool
  let onOpenFolder: (Folder) -> Void
  let onOpenNote: (Note) -> Void
  let onCreateFolder: () -> Void
  let onCreateNote: () -> Void
  let onOpenSettings: () -> Void
  let onRenameFolder: (Folder) -> Void
  let onMoveFolder: (Folder) -> Void
  let onDeleteFolder: (Folder) -> Void
  let onRenameNote: (Note) -> Void
  let onMoveNote: (Note) -> Void
  let onDeleteNote: (Note) -> Void

  @State private var searchText = ""

  private let columns = [
    GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 18)
  ]

  private var matchingNotes: [Note] {
    guard !searchText.isEmpty else { return notes }
    return notes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
  }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 28) {
        if !folders.isEmpty {
          browserSection(title: "Folders", count: folders.count) {
            folderGrid
          }
        }

        if !matchingNotes.isEmpty {
          browserSection(title: "Notes", count: matchingNotes.count) {
            noteGrid
          }
        } else if !searchText.isEmpty {
          noSearchResults
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(24)
    }
    .background(WhyboardTheme.warmBackground)
    .overlay { emptyState }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.large)
    .searchable(text: $searchText, prompt: "Search notes in this folder")
    .toolbar { browserToolbar }
  }

  private var folderGrid: some View {
    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
      ForEach(folders) { folder in
        Button {
          onOpenFolder(folder)
        } label: {
          FolderCard(folder: folder)
        }
        .buttonStyle(.plain)
        .contextMenu { folderActions(folder) }
      }
    }
  }

  private var noteGrid: some View {
    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
      ForEach(matchingNotes) { note in
        Button {
          onOpenNote(note)
        } label: {
          NoteCard(
            note: note,
            pageCount: pageCounts[note.id, default: 0],
            previewPage: coverPages[note.id],
            drawingRepository: drawingRepository)
        }
        .buttonStyle(.plain)
        .contextMenu { noteActions(note) }
      }
    }
  }

  @ViewBuilder
  private var emptyState: some View {
    if folders.isEmpty, notes.isEmpty, searchText.isEmpty {
      ContentUnavailableView {
        Label("This folder is ready", systemImage: "folder.badge.plus")
      } description: {
        Text("Create a folder or a note to start organising your work.")
      } actions: {
        HStack {
          Button("New Folder", action: onCreateFolder)
            .buttonStyle(.bordered)
          Button("New Note", action: onCreateNote)
            .buttonStyle(.borderedProminent)
        }
      }
    }
  }

  private var noSearchResults: some View {
    ContentUnavailableView.search(text: searchText)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 50)
  }

  @ToolbarContentBuilder
  private var browserToolbar: some ToolbarContent {
    ToolbarItemGroup(placement: .primaryAction) {
      if showsSettings {
        Button("Settings", systemImage: "gearshape", action: onOpenSettings)
      }
      Button("New Folder", systemImage: "folder.badge.plus", action: onCreateFolder)
      Button("New Note", systemImage: "square.and.pencil", action: onCreateNote)
    }
  }

  private func browserSection<Content: View>(
    title: String,
    count: Int,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline) {
        Text(title)
          .font(.title2.bold())
        Text("\(count)")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      content()
    }
  }

  @ViewBuilder
  private func folderActions(_ folder: Folder) -> some View {
    Button("Rename", systemImage: "pencil") { onRenameFolder(folder) }
    Button("Move", systemImage: "folder") { onMoveFolder(folder) }
    Divider()
    Button("Delete", systemImage: "trash", role: .destructive) {
      onDeleteFolder(folder)
    }
  }

  @ViewBuilder
  private func noteActions(_ note: Note) -> some View {
    Button("Rename", systemImage: "pencil") { onRenameNote(note) }
    Button("Move", systemImage: "folder") { onMoveNote(note) }
    Divider()
    Button("Delete", systemImage: "trash", role: .destructive) {
      onDeleteNote(note)
    }
  }
}

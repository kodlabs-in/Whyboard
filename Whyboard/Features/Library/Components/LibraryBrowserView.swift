import SwiftUI

struct LibraryBrowserView: View {
  let title: String
  let folders: [Folder]
  let notes: [Note]
  let favoriteNotes: [Note]
  let recentNotes: [Note]
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
  let onDuplicateNote: (Note) -> Void
  let onToggleFavorite: (Note) -> Void
  let onDeleteNote: (Note) -> Void
  let onImportPDF: () -> Void
  let onExportNote: (Note) -> Void
  let onMoveSelection: () -> Void
  let onDeleteSelection: () -> Void

  @Binding var sortField: NoteSortField
  @Binding var sortDirection: NoteSortDirection
  @Binding var isSelecting: Bool
  @Binding var selection: Set<LibrarySelectionItem>
  @State private var searchText = ""
  @State private var keyboardSelectionIndex = 0

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
        smartSections
        folderSection
        noteSection
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
    .safeAreaInset(edge: .bottom) { selectionToolbar }
  }

  @ViewBuilder
  private var smartSections: some View {
    if !isSelecting, !favoriteNotes.isEmpty {
      browserSection(title: "Favorites", count: favoriteNotes.count) {
        smartNoteStrip(favoriteNotes)
      }
    }

    if !isSelecting, !recentNotes.isEmpty {
      browserSection(title: "Recent", count: recentNotes.count) {
        smartNoteStrip(recentNotes)
      }
    }
  }

  @ViewBuilder
  private var folderSection: some View {
    if !folders.isEmpty {
      browserSection(title: "Folders", count: folders.count) {
        folderGrid
      }
    }
  }

  @ViewBuilder
  private var noteSection: some View {
    if !matchingNotes.isEmpty {
      browserSection(title: "Notes", count: matchingNotes.count) {
        noteGrid
      }
    } else if !searchText.isEmpty {
      noSearchResults
    }
  }

  private var folderGrid: some View {
    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
      ForEach(folders) { folder in
        Button {
          handleFolderTap(folder)
        } label: {
          FolderCard(
            folder: folder,
            isSelecting: isSelecting,
            isSelected: selection.contains(.folder(folder.id)))
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .contextMenu { if !isSelecting { folderActions(folder) } }
      }
    }
  }

  private var noteGrid: some View {
    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
      ForEach(matchingNotes) { note in
        noteCard(note)
      }
    }
  }

  private func smartNoteStrip(_ notes: [Note]) -> some View {
    ScrollView(.horizontal) {
      LazyHStack(alignment: .top, spacing: 16) {
        ForEach(notes) { note in
          noteCard(note)
            .frame(width: 210)
        }
      }
      .scrollTargetLayout()
    }
    .scrollIndicators(.hidden)
  }

  private func noteCard(_ note: Note) -> some View {
    NoteCard(
      note: note,
      pageCount: pageCounts[note.id, default: 0],
      previewPage: coverPages[note.id],
      drawingRepository: drawingRepository,
      isSelecting: isSelecting,
      isSelected: selection.contains(.note(note.id)),
      onOpen: { handleNoteTap(note) },
      onToggleFavorite: { onToggleFavorite(note) }
    )
    .hoverEffect(.lift)
    .contextMenu { if !isSelecting { noteActions(note) } }
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
      if showsSettings, !isSelecting {
        Button("Settings", systemImage: "gearshape", action: onOpenSettings)
      }
      if !isSelecting {
        Menu("Sort Notes", systemImage: "arrow.up.arrow.down") {
          Picker("Sort by", selection: $sortField) {
            ForEach(NoteSortField.allCases) { field in
              Text(field.title).tag(field)
            }
          }
          Picker("Direction", selection: $sortDirection) {
            ForEach(NoteSortDirection.allCases) { direction in
              Text(direction.title).tag(direction)
            }
          }
        }
        .accessibilityLabel(
          "Sort notes, \(sortField.title), \(sortDirection.title)")
        Button("New Folder", systemImage: "folder.badge.plus", action: onCreateFolder)
          .keyboardShortcut("n", modifiers: [.command, .shift])
        Button("New Note", systemImage: "square.and.pencil", action: onCreateNote)
          .keyboardShortcut("n", modifiers: .command)
        Button("Import PDF", systemImage: "square.and.arrow.down", action: onImportPDF)
      }
      Button(isSelecting ? "Done" : "Select", systemImage: selectionSystemImage) {
        setSelecting(!isSelecting)
      }
      .accessibilityIdentifier("library-select-mode")
    }
  }
}

private extension LibraryBrowserView {
  @ViewBuilder
  private var selectionToolbar: some View {
    if isSelecting {
      HStack(spacing: 14) {
        Button("Select All", systemImage: "checkmark.circle") {
          selection.formUnion(visibleItems)
        }
        .keyboardShortcut("a", modifiers: .command)

        Button("Extend Selection Backward", systemImage: "arrow.left") {
          extendKeyboardSelection(by: -1)
        }
        .keyboardShortcut(.leftArrow, modifiers: .shift)

        Button("Extend Selection Forward", systemImage: "arrow.right") {
          extendKeyboardSelection(by: 1)
        }
        .keyboardShortcut(.rightArrow, modifiers: .shift)

        Spacer()

        Text("\(selection.count) selected")
          .font(.subheadline.weight(.semibold))
          .accessibilityIdentifier("library-selection-count")

        Spacer()

        Button("Move", systemImage: "folder", action: onMoveSelection)
          .disabled(selection.isEmpty)
        Button("Delete", systemImage: "trash", role: .destructive, action: onDeleteSelection)
          .disabled(selection.isEmpty)
        Button("Cancel", role: .cancel) { setSelecting(false) }
          .keyboardShortcut(.cancelAction)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
      .background(.bar)
      .accessibilityElement(children: .contain)
    }
  }

  private var visibleItems: Set<LibrarySelectionItem> {
    Set(orderedVisibleItems)
  }

  private var orderedVisibleItems: [LibrarySelectionItem] {
    folders.map { .folder($0.id) } + matchingNotes.map { .note($0.id) }
  }

  private var selectionSystemImage: String {
    isSelecting ? "checkmark.circle.fill" : "checkmark.circle"
  }

  private func handleFolderTap(_ folder: Folder) {
    guard isSelecting else {
      onOpenFolder(folder)
      return
    }
    toggle(.folder(folder.id))
  }

  private func handleNoteTap(_ note: Note) {
    guard isSelecting else {
      onOpenNote(note)
      return
    }
    toggle(.note(note.id))
  }

  private func toggle(_ item: LibrarySelectionItem) {
    if let index = orderedVisibleItems.firstIndex(of: item) {
      keyboardSelectionIndex = index
    }
    if selection.contains(item) {
      selection.remove(item)
    } else {
      selection.insert(item)
    }
  }

  private func extendKeyboardSelection(by offset: Int) {
    guard !orderedVisibleItems.isEmpty else { return }
    keyboardSelectionIndex = min(
      max(keyboardSelectionIndex + offset, 0),
      orderedVisibleItems.count - 1)
    selection.insert(orderedVisibleItems[keyboardSelectionIndex])
  }

  private func setSelecting(_ newValue: Bool) {
    isSelecting = newValue
    if !newValue {
      selection.removeAll()
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
    Button(
      note.isFavorite == true ? "Remove from Favorites" : "Add to Favorites",
      systemImage: note.isFavorite == true ? "star.slash" : "star"
    ) {
      onToggleFavorite(note)
    }
    Button("Rename", systemImage: "pencil") { onRenameNote(note) }
    Button("Move", systemImage: "folder") { onMoveNote(note) }
    Button("Duplicate", systemImage: "plus.square.on.square") { onDuplicateNote(note) }
      .keyboardShortcut("d", modifiers: .command)
    Button("Export PDF", systemImage: "square.and.arrow.up") { onExportNote(note) }
      .keyboardShortcut("p", modifiers: .command)
    Divider()
    Button("Delete", systemImage: "trash", role: .destructive) {
      onDeleteNote(note)
    }
  }
}

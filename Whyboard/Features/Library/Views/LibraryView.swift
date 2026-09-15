import SwiftData
import SwiftUI

struct LibraryView: View {
  @Environment(\.modelContext) private var modelContext
  @Query(sort: [SortDescriptor(\Folder.sortOrder), SortDescriptor(\Folder.name)])
  private var folders: [Folder]
  @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
  @Query(sort: \Page.sortOrder) private var pages: [Page]

  @AppStorage("lastOpenedNoteID") private var lastOpenedNoteID = ""
  @State private var controller = LibraryController()

  let drawingRepository: DrawingRepository

  private var pageCounts: [UUID: Int] {
    Dictionary(grouping: pages, by: \.noteID).mapValues(\.count)
  }

  private var mutationContext: LibraryMutationContext {
    LibraryMutationContext(
      folders: folders,
      notes: notes,
      pages: pages,
      modelContext: modelContext,
      drawingRepository: drawingRepository)
  }

  var body: some View {
    @Bindable var controller = controller

    NavigationSplitView {
      FolderSidebar(
        folders: folders,
        selection: $controller.location,
        onCreateFolder: presentNewFolder,
        onRenameFolder: presentFolderRename,
        onMoveFolder: presentFolderMove,
        onDeleteFolder: confirmFolderDeletion)
    } content: {
      NoteListView(
        title: controller.locationTitle(folders: folders),
        notes: controller.visibleNotes(from: notes),
        pageCounts: pageCounts,
        selection: $controller.selectedNoteID,
        searchText: $controller.searchText,
        onCreateNote: createNote,
        onRenameNote: presentNoteRename,
        onMoveNote: presentNoteMove,
        onDeleteNote: confirmNoteDeletion)
    } detail: {
      detailView
    }
    .tint(WhyboardTheme.accent)
    .sheet(item: $controller.nameEditor) { NameEditorSheet(request: $0) }
    .sheet(item: $controller.destinationPicker) { DestinationPickerSheet(request: $0) }
    .alert(
      controller.confirmation?.title ?? "Confirm",
      isPresented: $controller.confirmationIsPresented,
      presenting: controller.confirmation
    ) { request in
      Button("Cancel", role: .cancel) {}
      Button(request.actionTitle, role: .destructive, action: request.action)
    } message: { request in
      Text(request.message)
    }
    .alert(
      "Whyboard couldn't complete that change",
      isPresented: $controller.errorIsPresented
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(controller.errorMessage ?? "Please try again.")
    }
    .onAppear {
      controller.restoreLastOpenedNote(idString: lastOpenedNoteID, notes: notes)
    }
    .onChange(of: controller.location) { _, _ in controller.selectedNoteID = nil }
    .onChange(of: controller.selectedNoteID) { _, newValue in
      lastOpenedNoteID = newValue?.uuidString ?? ""
    }
  }

  @ViewBuilder
  private var detailView: some View {
    if let note = controller.selectedNote(in: notes) {
      NoteEditorView(note: note, drawingRepository: drawingRepository)
        .id(note.id)
    } else {
      ZStack {
        WhyboardTheme.chromeBackground.ignoresSafeArea()
        ContentUnavailableView {
          Label("Ready when you are", systemImage: "pencil.and.outline")
        } description: {
          Text("Choose a note, or create one to begin writing.")
        }
      }
    }
  }

  private func presentNewFolder() {
    controller.presentNewFolder(folders: folders, context: modelContext)
  }

  private func presentFolderRename(_ folder: Folder) {
    controller.presentFolderRename(folder, context: modelContext)
  }

  private func presentFolderMove(_ folder: Folder) {
    controller.presentFolderMove(folder, folders: folders, context: modelContext)
  }

  private func confirmFolderDeletion(_ folder: Folder) {
    controller.confirmFolderDeletion(
      folder,
      mutationContext: mutationContext)
  }

  private func createNote() {
    controller.createNote(folders: folders, context: modelContext)
  }

  private func presentNoteRename(_ note: Note) {
    controller.presentNoteRename(note, context: modelContext)
  }

  private func presentNoteMove(_ note: Note) {
    controller.presentNoteMove(note, folders: folders, context: modelContext)
  }

  private func confirmNoteDeletion(_ note: Note) {
    controller.confirmNoteDeletion(
      note,
      pages: pages,
      context: modelContext,
      drawingRepository: drawingRepository)
  }
}

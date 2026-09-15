import SwiftData
import SwiftUI

struct LibraryView: View {
  @Environment(\.modelContext) private var modelContext
  @Query(sort: [SortDescriptor(\Folder.sortOrder), SortDescriptor(\Folder.name)])
  private var folders: [Folder]
  @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
  @Query(sort: \Page.sortOrder) private var pages: [Page]

  @State private var controller = LibraryController()
  @State private var routes: [LibraryRoute] = []
  @State private var noteCreationRequest: NoteCreationRequest?

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

    NavigationStack(path: $routes) {
      browserView(for: .root)
        .navigationDestination(for: LibraryRoute.self) { route in
          routeDestination(route)
        }
    }
    .tint(WhyboardTheme.accent)
    .sheet(item: $controller.nameEditor) { NameEditorSheet(request: $0) }
    .sheet(item: $controller.destinationPicker) { DestinationPickerSheet(request: $0) }
    .sheet(item: $noteCreationRequest) { request in
      NewNoteTypeSheet { kind in
        createNote(in: request.location, kind: kind)
      }
    }
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
  }

  @ViewBuilder
  private func routeDestination(_ route: LibraryRoute) -> some View {
    switch route {
    case .folder(let folderID):
      if folders.contains(where: { $0.id == folderID && !$0.isSystem }) {
        browserView(for: .folder(folderID))
      } else {
        ContentUnavailableView("Folder unavailable", systemImage: "folder.badge.questionmark")
      }
    case .note(let noteID):
      if let note = notes.first(where: { $0.id == noteID }) {
        noteDestination(note)
      } else {
        ContentUnavailableView("Note unavailable", systemImage: "note.text")
      }
    case .settings:
      SettingsView()
    }
  }

  @ViewBuilder
  private func noteDestination(_ note: Note) -> some View {
    switch note.kind {
    case .infinitePages:
      NoteEditorView(note: note, drawingRepository: drawingRepository)
        .id(note.id)
    case .infiniteCanvas:
      InfiniteCanvasEditorView(note: note, drawingRepository: drawingRepository)
        .id(note.id)
    }
  }

  private func browserView(for location: LibraryLocation) -> some View {
    LibraryBrowserView(
      title: controller.locationTitle(location, folders: folders),
      folders: controller.folders(in: location, from: folders),
      notes: controller.notes(in: location, from: notes, folders: folders),
      pageCounts: pageCounts,
      showsSettings: location == .root,
      onOpenFolder: { routes.append(.folder($0.id)) },
      onOpenNote: { routes.append(.note($0.id)) },
      onCreateFolder: { presentNewFolder(in: location) },
      onCreateNote: { presentNoteCreation(in: location) },
      onOpenSettings: { routes.append(.settings) },
      onRenameFolder: presentFolderRename,
      onMoveFolder: presentFolderMove,
      onDeleteFolder: confirmFolderDeletion,
      onRenameNote: presentNoteRename,
      onMoveNote: presentNoteMove,
      onDeleteNote: confirmNoteDeletion)
  }

  private func presentNewFolder(in location: LibraryLocation) {
    controller.presentNewFolder(in: location, folders: folders, context: modelContext)
  }

  private func presentFolderRename(_ folder: Folder) {
    controller.presentFolderRename(folder, context: modelContext)
  }

  private func presentFolderMove(_ folder: Folder) {
    controller.presentFolderMove(folder, folders: folders, context: modelContext)
  }

  private func confirmFolderDeletion(_ folder: Folder) {
    controller.confirmFolderDeletion(folder, mutationContext: mutationContext)
  }

  private func presentNoteCreation(in location: LibraryLocation) {
    noteCreationRequest = NoteCreationRequest(location: location)
  }

  private func createNote(in location: LibraryLocation, kind: NoteKind) {
    noteCreationRequest = nil
    guard
      let noteID = controller.createNote(
        in: location,
        kind: kind,
        folders: folders,
        context: modelContext)
    else { return }
    routes.append(.note(noteID))
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

private enum LibraryRoute: Hashable {
  case folder(UUID)
  case note(UUID)
  case settings
}

private struct NoteCreationRequest: Identifiable {
  let id = UUID()
  let location: LibraryLocation
}

import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct LibraryView: View {
  @Environment(\.modelContext) var modelContext
  @Query(sort: [SortDescriptor(\Folder.sortOrder), SortDescriptor(\Folder.name)])
  var folders: [Folder]
  @Query(sort: \Note.updatedAt, order: .reverse) var notes: [Note]
  @Query(sort: \Page.sortOrder) var pages: [Page]
  @Query private var importedDocuments: [ImportedDocument]

  @AppStorage(NoteSortField.storageKey, store: AppPreferences.store)
  private var noteSortField = NoteSortField.updatedDate
  @AppStorage(NoteSortDirection.storageKey, store: AppPreferences.store)
  private var noteSortDirection = NoteSortDirection.descending

  @State var controller = LibraryController()
  @State var routes: [LibraryRoute] = []
  @State private var noteCreationRequest: NoteCreationRequest?
  @State private var isDuplicatingNote = false
  @State private var isSelecting = false
  @State private var selection: Set<LibrarySelectionItem> = []
  @State var isPickingPDF = false
  @State var pdfImportLocation = LibraryLocation.root
  @State var documentOperation: DocumentOperationPresentation?
  @State var documentTask: Task<Void, Never>?
  @State var exportedPDF: PDFExportResult?

  let drawingRepository: DrawingRepository

  private var pageCounts: [UUID: Int] {
    Dictionary(grouping: pages, by: \.noteID).mapValues(\.count)
  }

  private var sortedNotes: [Note] {
    NoteSorting.sorted(notes, by: noteSortField, direction: noteSortDirection)
  }

  private var favoriteNotes: [Note] {
    sortedNotes.filter { $0.isFavorite == true }
  }

  private var recentNotes: [Note] {
    NoteSorting.recentlyOpened(notes)
  }

  private var coverPages: [UUID: Page] {
    pages.reduce(into: [:]) { result, page in
      let currentOrder = result[page.noteID]?.sortOrder ?? Int.max
      guard page.sortOrder < currentOrder else { return }
      result[page.noteID] = page
    }
  }

  private var mutationContext: LibraryMutationContext {
    LibraryMutationContext(
      folders: folders,
      notes: notes,
      pages: pages,
      importedDocuments: importedDocuments,
      modelContext: modelContext,
      drawingRepository: drawingRepository)
  }

  private var selectionPlan: LibrarySelectionPlan {
    LibrarySelectionPlan(
      selection: selection,
      folders: folders,
      notes: notes,
      pages: pages)
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
    .sheet(item: $documentOperation) { operation in
      DocumentProgressSheet(operation: operation, onCancel: cancelDocumentOperation)
    }
    .sheet(item: $exportedPDF, onDismiss: removeExportedPDF) { export in
      PDFShareSheet(url: export.url)
    }
    .fileImporter(
      isPresented: $isPickingPDF,
      allowedContentTypes: [.pdf],
      allowsMultipleSelection: false,
      onCompletion: handlePDFSelection
    )
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
    .onReceive(
      NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
    ) { _ in
      clearDisposableCaches()
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: UIApplication.didReceiveMemoryWarningNotification)
    ) { _ in
      clearDisposableCaches()
    }
    .onReceive(
      NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
    ) { _ in
      guard !ThermalPolicy.allowsSpeculativeWork else { return }
      clearDisposableCaches()
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
      SettingsView(drawingRepository: drawingRepository)
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
      notes: controller.notes(in: location, from: sortedNotes, folders: folders),
      favoriteNotes: location == .root ? favoriteNotes : [],
      recentNotes: location == .root ? recentNotes : [],
      pageCounts: pageCounts,
      coverPages: coverPages,
      drawingRepository: drawingRepository,
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
      onDuplicateNote: duplicateNote,
      onToggleFavorite: toggleFavorite,
      onDeleteNote: confirmNoteDeletion,
      onImportPDF: { presentPDFImport(in: location) },
      onExportNote: exportNote,
      onMoveSelection: presentSelectionMove,
      onDeleteSelection: confirmSelectionDeletion,
      sortField: $noteSortField,
      sortDirection: $noteSortDirection,
      isSelecting: $isSelecting,
      selection: $selection)
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

  private func duplicateNote(_ note: Note) {
    guard !isDuplicatingNote else { return }
    isDuplicatingNote = true

    Task {
      defer { isDuplicatingNote = false }
      do {
        _ = try await DuplicationService(drawingRepository: drawingRepository)
          .duplicateNote(
            note,
            pages: pages,
            notes: notes,
            documents: importedDocuments,
            context: modelContext)
      } catch {
        controller.errorMessage = error.localizedDescription
      }
    }
  }

  private func toggleFavorite(_ note: Note) {
    note.isFavorite = note.isFavorite == true ? nil : true
    controller.save(modelContext)
  }

  private func confirmNoteDeletion(_ note: Note) {
    controller.confirmNoteDeletion(
      note,
      pages: pages,
      importedDocuments: importedDocuments,
      context: modelContext,
      drawingRepository: drawingRepository)
  }
}

private extension LibraryView {
  private func clearDisposableCaches() {
    Task {
      await drawingRepository.previews.clearMemoryCache()
      await AttachmentImageCache.shared.clear()
    }
  }

  private func presentSelectionMove() {
    let plan = selectionPlan
    guard !plan.isEmpty else { return }
    controller.destinationPicker = DestinationPickerRequest(
      title: "Move \(selection.count) Items",
      destinations: FolderHierarchy.destinations(
        from: folders,
        excluding: plan.excludedDestinationIDs,
        includeRoot: true),
      currentFolderID: nil,
      allowsCurrentDestination: true
    ) { destination in
      performSelectionMove(plan: plan, destination: destination)
    }
  }

  private func performSelectionMove(plan: LibrarySelectionPlan, destination: Folder?) {
    do {
      try BulkLibraryService().move(
        plan: plan,
        to: destination,
        folders: folders,
        notes: notes,
        context: modelContext)
      finishSelection()
      UIAccessibility.post(notification: .announcement, argument: "Selected items moved")
    } catch {
      controller.errorMessage = error.localizedDescription
    }
  }

  private func confirmSelectionDeletion() {
    let plan = selectionPlan
    guard !plan.isEmpty else { return }
    controller.confirmation = ConfirmationRequest(
      title: "Delete \(selection.count) Selected Items?",
      message: plan.impact.summary,
      actionTitle: "Delete All"
    ) {
      performSelectionDeletion(plan)
    }
  }

  private func performSelectionDeletion(_ plan: LibrarySelectionPlan) {
    do {
      try BulkLibraryService().delete(
        plan: plan,
        mutationContext: mutationContext)
      finishSelection()
      UIAccessibility.post(
        notification: .announcement,
        argument: "Deletion complete. \(plan.impact.summary)")
    } catch {
      controller.errorMessage = error.localizedDescription
    }
  }

  private func finishSelection() {
    selection.removeAll()
    isSelecting = false
  }
}

enum LibraryRoute: Hashable {
  case folder(UUID)
  case note(UUID)
  case settings
}

private struct NoteCreationRequest: Identifiable {
  let id = UUID()
  let location: LibraryLocation
}

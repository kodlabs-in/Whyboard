// swiftlint:disable file_length
import Combine
import Foundation
import SwiftData
import SwiftUI
import UIKit

struct NoteEditorView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Query private var pages: [Page]

  @AppStorage("drawWithFinger", store: AppPreferences.store) private var drawsWithFinger = false
  @State private var controller: EditorController
  @State private var toolPickerController = ToolPickerController()
  @State private var elementEditingController: WorkspaceElementEditingController
  @State private var scrollPosition: ScrollPosition
  @State private var currentScrollOffset: Double
  @State private var pendingScrollPageID: UUID?
  @State private var pageToDelete: Page?
  @State private var showsPageOrganizer = false
  @State private var showsJumpToPage = false
  @State private var duplicatingPageID: UUID?
  @State private var nameEditor: NameEditorRequest?
  @State private var exportController = NoteExportController()

  let note: Note
  let drawingRepository: DrawingRepository

  init(note: Note, drawingRepository: DrawingRepository) {
    self.note = note
    self.drawingRepository = drawingRepository
    let noteID = note.id
    _pages = Query(
      filter: #Predicate<Page> { $0.noteID == noteID },
      sort: \Page.sortOrder)
    _controller = State(
      initialValue: EditorController(note: note, drawingRepository: drawingRepository))
    _elementEditingController = State(
      initialValue: WorkspaceElementEditingController(
        noteID: note.id,
        attachments: drawingRepository.attachments))
    _scrollPosition = State(
      initialValue: ScrollPosition(y: max(0, note.lastScrollOffset)))
    _currentScrollOffset = State(initialValue: max(0, note.lastScrollOffset))
  }

  private var orderedPages: [Page] {
    PageOrdering.ordered(pages)
  }
  private var orderedPageIDs: [UUID] { orderedPages.map(\.id) }
  private var resolvedPaperStyle: NotePaperStyle {
    note.paperStyle.resolved(defaultRawValue: NotePaperStyle.defaultStyle.rawValue)
  }

  var body: some View {
    GeometryReader { geometry in
      ScrollView(.vertical) {
        LazyVStack(spacing: 28) {
          ForEach(Array(orderedPages.enumerated()), id: \.element.id) { index, page in
            pageView(page, index: index, availableWidth: geometry.size.width)
          }

          EditorAddPageButton(action: appendPage)
        }
        .scrollTargetLayout()
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
      }
      .scrollPosition($scrollPosition)
      .onScrollGeometryChange(for: Double.self) { geometry in
        max(0, Double(geometry.contentOffset.y + geometry.contentInsets.top))
      } action: { _, newValue in
        currentScrollOffset = newValue
        let pageWidth = max(260, min(geometry.size.width - 48, 900))
        controller.updateActivePage(
          scrollOffset: newValue,
          viewportHeight: geometry.size.height,
          pageHeight: pageWidth / WhyboardTheme.pageAspectRatio,
          orderedPageIDs: orderedPageIDs)
      }
      .onScrollPhaseChange { _, phase in
        if phase == .idle {
          persistScrollPosition()
        }
      }
    }
    .background(WhyboardTheme.warmBackground)
    .navigationTitle(note.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(WhyboardTheme.chromeBackground, for: .navigationBar)
    .toolbarBackground(.visible, for: .navigationBar)
    .toolbar { editorToolbar }
    .workspaceElementEditing(elementEditingController)
    .noteExportPresentation(exportController)
    .safeAreaInset(edge: .top) {
      EditorSaveErrorBanner(status: controller.saveStatus) {
        Task { await controller.flushAll() }
      }
    }
    .sheet(isPresented: $showsPageOrganizer) {
      PageOrganizerSheet(
        note: note,
        pages: orderedPages,
        currentPageID: controller.activePageID,
        drawingRepository: drawingRepository,
        onSelect: scrollToPage,
        onMove: movePages)
    }
    .sheet(isPresented: $showsJumpToPage) {
      JumpToPageSheet(
        note: note,
        pages: orderedPages,
        currentPageID: controller.activePageID,
        drawingRepository: drawingRepository,
        onSelect: scrollToPage)
    }
    .sheet(item: $nameEditor) { NameEditorSheet(request: $0) }
    .alert(
      "Delete page?",
      isPresented: pageDeletionIsPresented,
      presenting: pageToDelete
    ) { page in
      Button("Cancel", role: .cancel) {}
      Button("Delete Page", role: .destructive) { deletePage(page) }
    } message: { _ in
      Text("This permanently deletes the drawing on this page.")
    }
    .alert("Whyboard couldn't complete that change", isPresented: errorIsPresented) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(controller.errorMessage ?? "Please try again.")
    }
    .onAppear { prepareEditor() }
    .onDisappear {
      Task { await controller.close() }
    }
    .onChange(of: orderedPageIDs) { _, _ in
      controller.reconcile(pages: orderedPages)
      performPendingScrollIfReady()
    }
    .onChange(of: scenePhase) { _, newPhase in
      guard newPhase != .active else { return }
      persistScrollPosition()
      Task { await controller.flushAll() }
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: UIApplication.didReceiveMemoryWarningNotification)
    ) { _ in
      controller.handleMemoryWarning()
    }
  }

  private func pageView(_ page: Page, index: Int, availableWidth: CGFloat) -> some View {
    let session = controller.session(for: page)
    let elementSession = controller.elementSession(for: page, canvasSize: CanonicalPage.size)
    let pageWidth = max(260, min(availableWidth - 48, 900))

    return PagePaperView(
      page: page,
      pageNumber: index + 1,
      pageCount: orderedPages.count,
      isLive: controller.livePageIDs.contains(page.id),
      paperStyle: resolvedPaperStyle,
      drawsWithFinger: drawsWithFinger,
      interactionMode: elementEditingController.interactionMode,
      session: session,
      elementSession: elementSession,
      drawingRepository: drawingRepository,
      toolPickerController: toolPickerController,
      onFocus: { controller.focus(page.id) },
      onElementActivate: { element in
        elementEditingController.activate(element, in: elementSession)
      },
      onInsertBefore: { insertPage(relativeTo: page, after: false) },
      onInsertAfter: { insertPage(relativeTo: page, after: true) },
      onDuplicate: { duplicatePage(page) },
      onDelete: { pageToDelete = page }
    )
    .frame(width: pageWidth)
    .id(page.id)
    .onAppear { controller.pageAppeared(page.id, orderedPageIDs: orderedPageIDs) }
    .onDisappear { controller.pageDisappeared(page.id, orderedPageIDs: orderedPageIDs) }
  }

  @ToolbarContentBuilder
  private var editorToolbar: some ToolbarContent {
    ToolbarItem(placement: .topBarLeading) {
      EditorSaveStatusView(status: controller.saveStatus)
    }

    ToolbarItemGroup(placement: .primaryAction) {
      Button("Undo", systemImage: "arrow.uturn.backward") {
        Task { await controller.undoHistory.undo() }
      }
      .keyboardShortcut("z", modifiers: .command)
      .disabled(!controller.undoHistory.canUndo)

      Button("Redo", systemImage: "arrow.uturn.forward") {
        Task { await controller.undoHistory.redo() }
      }
      .keyboardShortcut("z", modifiers: [.command, .shift])
      .disabled(!controller.undoHistory.canRedo)

      Button("Add Page", systemImage: "plus", action: appendPage)

      Button("Arrange Pages", systemImage: "rectangle.3.group", action: showPageOrganizer)

      Button(
        "Jump to Page",
        systemImage: WhyboardSymbols.jumpToPage,
        action: showJumpToPage
      )
      .keyboardShortcut("g", modifiers: .command)
      .accessibilityIdentifier("jump-to-page")

      WorkspaceObjectToolbar(controller: elementEditingController)

      NoteOptionsMenu(
        paperStyle: paperStyleSelection,
        drawsWithFinger: $drawsWithFinger,
        onRename: presentRename,
        onDuplicate: duplicateCurrentPage,
        onExportPDF: exportPDF,
        onPreviousPage: { movePage(by: -1) },
        onNextPage: { movePage(by: 1) })
    }
  }

  private var pageDeletionIsPresented: Binding<Bool> {
    Binding(
      get: { pageToDelete != nil },
      set: { if !$0 { pageToDelete = nil } })
  }

  private var errorIsPresented: Binding<Bool> {
    Binding(
      get: { controller.errorMessage != nil },
      set: { if !$0 { controller.errorMessage = nil } })
  }

  private var paperStyleSelection: Binding<NotePaperStyle> {
    Binding(
      get: { note.paperStyle },
      set: { style in
        note.paperStyle = style
        note.updatedAt = Date()
        try? modelContext.save()
      })
  }
}

private extension NoteEditorView {
  private func prepareEditor() {
    controller.configure { try modelContext.save() }
    elementEditingController.configure(
      resolveTarget: elementEditingTarget,
      onError: { controller.errorMessage = $0 })
    note.lastOpenedAt = Date()

    if pages.isEmpty {
      _ = controller.appendPage(pages: pages, context: modelContext)
    } else {
      try? modelContext.save()
    }
  }

  private func elementEditingTarget(for requestedPageID: UUID?) -> ElementEditingTarget? {
    let pageID = requestedPageID ?? controller.activePageID ?? orderedPages.first?.id
    guard let page = orderedPages.first(where: { $0.id == pageID }) else { return nil }
    return ElementEditingTarget(
      pageID: page.id,
      session: controller.elementSession(for: page, canvasSize: CanonicalPage.size),
      insertionPoint: CGPoint(x: CanonicalPage.size.width / 2, y: CanonicalPage.size.height / 2))
  }

  private func appendPage() {
    let pageID = controller.appendPage(pages: pages, context: modelContext)
    scrollToPage(pageID)
  }

  private func insertPage(relativeTo page: Page, after: Bool) {
    let pageID = controller.insertPage(
      relativeTo: page,
      after: after,
      pages: pages,
      context: modelContext)
    scrollToPage(pageID)
  }

  private func duplicatePage(_ page: Page) {
    guard duplicatingPageID == nil else { return }
    duplicatingPageID = page.id

    Task {
      defer { duplicatingPageID = nil }
      do {
        let pageID = try await DuplicationService(drawingRepository: drawingRepository)
          .duplicatePage(page, in: pages, note: note, context: modelContext)
        scrollToPage(pageID)
      } catch {
        controller.errorMessage = error.localizedDescription
      }
    }
  }

  private func scrollToPage(_ pageID: UUID) {
    controller.focus(pageID)
    pendingScrollPageID = pageID
    performPendingScrollIfReady()
  }

  private func performPendingScrollIfReady() {
    guard
      let pageID = pendingScrollPageID,
      orderedPageIDs.contains(pageID)
    else { return }
    pendingScrollPageID = nil

    Task { @MainActor in
      await Task.yield()
      if reduceMotion {
        scrollPosition.scrollTo(id: pageID, anchor: .center)
      } else {
        withAnimation(.smooth) {
          scrollPosition.scrollTo(id: pageID, anchor: .center)
        }
      }
      if let pageIndex = orderedPages.firstIndex(where: { $0.id == pageID }) {
        UIAccessibility.post(
          notification: .announcement,
          argument: "Page \(pageIndex + 1) of \(orderedPages.count)")
      }
    }
  }

  private func duplicateCurrentPage() {
    let pageID = controller.activePageID ?? orderedPages.first?.id
    guard let page = orderedPages.first(where: { $0.id == pageID }) else { return }
    duplicatePage(page)
  }

  private func movePage(by offset: Int) {
    guard !orderedPages.isEmpty else { return }
    let currentID = controller.activePageID ?? orderedPages.first?.id
    let currentIndex = orderedPages.firstIndex { $0.id == currentID } ?? 0
    let targetIndex = min(max(currentIndex + offset, 0), orderedPages.count - 1)
    scrollToPage(orderedPages[targetIndex].id)
  }

  private func exportPDF() {
    exportController.export(
      note: note,
      pages: orderedPages,
      defaultPaperStyle: resolvedPaperStyle,
      drawingRepository: drawingRepository)
  }

  private func deletePage(_ page: Page) {
    pageToDelete = nil
    let wasActivePage = controller.activePageID == page.id
    Task {
      let didDelete = await controller.deletePage(page, pages: pages, context: modelContext)
      if didDelete, wasActivePage, let pageID = controller.activePageID {
        scrollToPage(pageID)
      }
    }
  }

  private func movePages(from offsets: IndexSet, to destination: Int) {
    controller.movePages(
      from: offsets,
      to: destination,
      pages: pages,
      context: modelContext)
  }

  private func showPageOrganizer() {
    showsPageOrganizer = true
  }

  private func showJumpToPage() {
    showsJumpToPage = true
  }

  private func presentRename() {
    nameEditor = NameEditorRequest(
      title: "Rename Note",
      prompt: "Note title",
      initialName: note.title,
      systemImage: "note.text"
    ) { title in
      note.title = title
      note.updatedAt = Date()
      try? modelContext.save()
    }
  }

  private func persistScrollPosition() {
    guard abs(note.lastScrollOffset - currentScrollOffset) > 0.5 else { return }
    note.lastScrollOffset = currentScrollOffset
    try? modelContext.save()
  }
}

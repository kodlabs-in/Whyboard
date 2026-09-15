import Combine
import Foundation
import SwiftData
import SwiftUI
import UIKit

struct NoteEditorView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.scenePhase) private var scenePhase
  @Query private var pages: [Page]

  @AppStorage("drawWithFinger") private var drawsWithFinger = false
  @State private var controller: EditorController
  @State private var toolPickerController = ToolPickerController()
  @State private var scrollPosition: ScrollPosition
  @State private var currentScrollOffset: Double
  @State private var pageToDelete: Page?
  @State private var showsPageOrganizer = false
  @State private var nameEditor: NameEditorRequest?

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
    _scrollPosition = State(
      initialValue: ScrollPosition(y: max(0, note.lastScrollOffset)))
    _currentScrollOffset = State(initialValue: max(0, note.lastScrollOffset))
  }

  private var orderedPages: [Page] {
    PageOrdering.ordered(pages)
  }

  private var orderedPageIDs: [UUID] {
    orderedPages.map(\.id)
  }

  var body: some View {
    GeometryReader { geometry in
      ScrollView(.vertical) {
        LazyVStack(spacing: 28) {
          ForEach(Array(orderedPages.enumerated()), id: \.element.id) { index, page in
            pageView(page, index: index, availableWidth: geometry.size.width)
          }

          addPageButton
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
    .safeAreaInset(edge: .top) { saveErrorBanner }
    .sheet(isPresented: $showsPageOrganizer) {
      PageOrganizerSheet(pages: orderedPages, onMove: movePages)
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
    .onDisappear { Task { await controller.flushAll() } }
    .onChange(of: orderedPageIDs) { _, _ in controller.reconcile(pages: orderedPages) }
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
    let pageWidth = max(260, min(availableWidth - 48, 900))

    return PagePaperView(
      page: page,
      pageNumber: index + 1,
      pageCount: orderedPages.count,
      isLive: controller.livePageIDs.contains(page.id),
      drawsWithFinger: drawsWithFinger,
      session: session,
      drawingRepository: drawingRepository,
      toolPickerController: toolPickerController,
      onFocus: { controller.focus(page.id) },
      onInsertBefore: { insertPage(relativeTo: page, after: false) },
      onInsertAfter: { insertPage(relativeTo: page, after: true) },
      onDelete: { pageToDelete = page }
    )
    .frame(width: pageWidth)
    .id(page.id)
    .onAppear { controller.pageAppeared(page.id, orderedPageIDs: orderedPageIDs) }
    .onDisappear { controller.pageDisappeared(page.id, orderedPageIDs: orderedPageIDs) }
  }

  private var addPageButton: some View {
    Button(action: appendPage) {
      Label("Add Page", systemImage: "plus")
        .font(.headline)
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
    }
    .buttonStyle(.borderedProminent)
    .buttonBorderShape(.capsule)
    .padding(.bottom, 40)
    .accessibilityHint("Appends a blank page to this note")
  }

  @ToolbarContentBuilder
  private var editorToolbar: some ToolbarContent {
    ToolbarItem(placement: .topBarLeading) {
      EditorSaveStatusView(status: controller.saveStatus)
    }

    ToolbarItemGroup(placement: .primaryAction) {
      Button("Undo", systemImage: "arrow.uturn.backward", action: toolPickerController.undo)
        .keyboardShortcut("z", modifiers: .command)
        .disabled(!toolPickerController.canUndo)

      Button("Redo", systemImage: "arrow.uturn.forward", action: toolPickerController.redo)
        .keyboardShortcut("z", modifiers: [.command, .shift])
        .disabled(!toolPickerController.canRedo)

      Button("Add Page", systemImage: "plus", action: appendPage)

      Button("Arrange Pages", systemImage: "rectangle.3.group", action: showPageOrganizer)

      Menu("Note Options", systemImage: "ellipsis.circle") {
        Button("Rename Note", systemImage: "pencil", action: presentRename)
        Toggle("Draw with Finger", isOn: $drawsWithFinger)
      }
    }
  }

  @ViewBuilder
  private var saveErrorBanner: some View {
    if case .failed(let message) = controller.saveStatus {
      HStack(spacing: 10) {
        Image(systemName: "exclamationmark.triangle.fill")
        Text(message)
          .font(.callout)
        Spacer()
        Button("Retry") { Task { await controller.flushAll() } }
      }
      .foregroundStyle(.red)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(.regularMaterial)
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

  private func prepareEditor() {
    controller.configure { try modelContext.save() }
    note.lastOpenedAt = Date()

    if pages.isEmpty {
      _ = controller.appendPage(pages: pages, context: modelContext)
    } else {
      try? modelContext.save()
    }
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

  private func scrollToPage(_ pageID: UUID) {
    Task {
      try? await Task.sleep(for: .milliseconds(120))
      withAnimation(.smooth) {
        scrollPosition.scrollTo(id: pageID, anchor: .center)
      }
    }
  }

  private func deletePage(_ page: Page) {
    pageToDelete = nil
    controller.deletePage(page, pages: pages, context: modelContext)
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

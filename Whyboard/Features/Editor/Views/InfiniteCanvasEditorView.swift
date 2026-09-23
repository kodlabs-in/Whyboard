import Foundation
import PencilKit
import SwiftData
import SwiftUI
import UIKit

struct InfiniteCanvasEditorView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.scenePhase) private var scenePhase
  @Query private var pages: [Page]

  @AppStorage("drawWithFinger", store: AppPreferences.store) private var drawsWithFinger = false
  @State private var editorController: EditorController
  @State private var canvasController: InfiniteCanvasController
  @State private var toolPickerController = ToolPickerController()
  @State private var elementEditingController: WorkspaceElementEditingController
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
    _editorController = State(
      initialValue: EditorController(note: note, drawingRepository: drawingRepository))
    _canvasController = State(
      initialValue: InfiniteCanvasController(
        initialViewport: InfiniteCanvasViewport(storedIn: note)))
    _elementEditingController = State(
      initialValue: WorkspaceElementEditingController(
        noteID: note.id,
        attachments: drawingRepository.attachments))
  }

  private var page: Page? {
    PageOrdering.ordered(pages).first
  }

  private var resolvedPaperStyle: NotePaperStyle {
    note.paperStyle.resolved(defaultRawValue: NotePaperStyle.defaultStyle.rawValue)
  }

  var body: some View {
    canvasContent
      .background(WhyboardTheme.paperColor(for: resolvedPaperStyle))
      .navigationTitle(note.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(WhyboardTheme.chromeBackground, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .toolbar { editorToolbar }
      .workspaceElementEditing(elementEditingController)
      .noteExportPresentation(exportController)
      .safeAreaInset(edge: .top) {
        EditorSaveErrorBanner(status: editorController.saveStatus) {
          Task { await editorController.flushAll() }
        }
      }
      .sheet(item: $nameEditor) { NameEditorSheet(request: $0) }
      .alert("Whyboard couldn't complete that change", isPresented: errorIsPresented) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(editorController.errorMessage ?? "Please try again.")
      }
      .onAppear(perform: prepareEditor)
      .onDisappear(perform: saveAndClose)
      .onChange(of: scenePhase) { _, newPhase in
        guard newPhase != .active else { return }
        saveViewportAndDrawing()
      }
  }

  @ViewBuilder
  private var canvasContent: some View {
    if let page {
      let session = editorController.session(for: page)
      let elementSession = editorController.elementSession(
        for: page,
        canvasSize: InfiniteCanvasMetrics.contentSize)
      InfiniteCanvasSurface(
        page: page,
        session: session,
        elementSession: elementSession,
        drawsWithFinger: drawsWithFinger,
        interactionMode: elementEditingController.interactionMode,
        canvasController: canvasController,
        toolPickerController: toolPickerController,
        attachments: drawingRepository.attachments,
        onFocus: { editorController.focus(page.id) },
        onElementActivate: { element in
          elementEditingController.activate(element, in: elementSession)
        })
    } else {
      ProgressView("Preparing canvas")
        .tint(WhyboardTheme.accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  @ToolbarContentBuilder
  private var editorToolbar: some ToolbarContent {
    ToolbarItem(placement: .topBarLeading) {
      EditorSaveStatusView(status: editorController.saveStatus)
    }

    ToolbarItemGroup(placement: .primaryAction) {
      Button("Undo", systemImage: "arrow.uturn.backward") {
        Task { await editorController.undoHistory.undo() }
      }
      .keyboardShortcut("z", modifiers: .command)
      .disabled(!editorController.undoHistory.canUndo)

      Button("Redo", systemImage: "arrow.uturn.forward") {
        Task { await editorController.undoHistory.redo() }
      }
      .keyboardShortcut("z", modifiers: [.command, .shift])
      .disabled(!editorController.undoHistory.canRedo)

      Button("Zoom Out", systemImage: "minus.magnifyingglass", action: canvasController.zoomOut)
        .accessibilityIdentifier("canvas-zoom-out")

      Text(canvasController.zoomPercentage)
        .font(.caption.monospacedDigit())
        .frame(minWidth: 42)
        .accessibilityIdentifier("canvas-zoom-percentage")

      Button("Zoom In", systemImage: "plus.magnifyingglass", action: canvasController.zoomIn)
        .accessibilityIdentifier("canvas-zoom-in")

      Button("Reset View", systemImage: "scope", action: canvasController.resetView)

      WorkspaceObjectToolbar(controller: elementEditingController)

      NoteOptionsMenu(
        paperStyle: paperStyleSelection,
        drawsWithFinger: $drawsWithFinger,
        onRename: presentRename,
        onExportPDF: exportPDF)
    }
  }

  private var errorIsPresented: Binding<Bool> {
    Binding(
      get: { editorController.errorMessage != nil },
      set: { if !$0 { editorController.errorMessage = nil } })
  }

  private var paperStyleSelection: Binding<NotePaperStyle> {
    Binding(
      get: { note.paperStyle },
      set: updatePaperStyle)
  }

  private func prepareEditor() {
    editorController.configure { try modelContext.save() }
    canvasController.configure(onViewportChanged: persistViewport)
    elementEditingController.configure(
      resolveTarget: elementEditingTarget,
      onError: { editorController.errorMessage = $0 })
    note.lastOpenedAt = Date()

    if pages.isEmpty {
      _ = editorController.appendPage(pages: pages, context: modelContext)
    } else {
      try? modelContext.save()
    }
  }

  private func elementEditingTarget(for requestedPageID: UUID?) -> ElementEditingTarget? {
    guard let page, requestedPageID == nil || requestedPageID == page.id else { return nil }
    return ElementEditingTarget(
      pageID: page.id,
      session: editorController.elementSession(
        for: page,
        canvasSize: InfiniteCanvasMetrics.contentSize),
      insertionPoint: canvasController.visibleCenter)
  }

  private func saveAndClose() {
    canvasController.persistCurrentViewport()
    Task { await editorController.close() }
  }

  private func saveViewportAndDrawing() {
    canvasController.persistCurrentViewport()
    Task { await editorController.flushAll() }
  }

  private func persistViewport(_ viewport: InfiniteCanvasViewport) {
    guard viewport.differs(from: note) else { return }
    note.canvasOffsetX = Double(viewport.contentOffset.x)
    note.canvasOffsetY = Double(viewport.contentOffset.y)
    note.canvasZoomScale = Double(viewport.zoomScale)
    saveMetadata()
  }

  private func updatePaperStyle(_ style: NotePaperStyle) {
    note.paperStyle = style
    note.updatedAt = Date()
    saveMetadata()
  }

  private func presentRename() {
    nameEditor = NameEditorRequest(
      title: "Rename Note",
      prompt: "Note title",
      initialName: note.title,
      systemImage: "rectangle.dashed"
    ) { title in
      note.title = title
      note.updatedAt = Date()
      saveMetadata()
    }
  }

  private func exportPDF() {
    exportController.export(
      note: note,
      pages: pages,
      defaultPaperStyle: resolvedPaperStyle,
      drawingRepository: drawingRepository)
  }

  private func saveMetadata() {
    do {
      try modelContext.save()
    } catch {
      editorController.errorMessage = error.localizedDescription
    }
  }
}

private struct InfiniteCanvasSurface: View {
  let page: Page
  let session: PageSession
  let elementSession: ElementSession
  let drawsWithFinger: Bool
  let interactionMode: WorkspaceInteractionMode
  let canvasController: InfiniteCanvasController
  let toolPickerController: ToolPickerController
  let attachments: AttachmentRepository
  let onFocus: () -> Void
  let onElementActivate: (WorkspaceElement) -> Void

  var body: some View {
    Group {
      if session.isLoaded {
        infiniteWorkspace
      } else if case .failed(let message) = session.state {
        ContentUnavailableView {
          Label("Canvas unavailable", systemImage: "exclamationmark.triangle")
        } description: {
          Text(message)
        } actions: {
          Button("Try Again") {
            Task { await session.loadIfNeeded() }
          }
        }
      } else {
        ProgressView("Loading canvas")
          .tint(WhyboardTheme.accent)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .task(id: page.id) {
      await session.loadIfNeeded()
    }
  }

  private var infiniteWorkspace: some View {
    let transform = WorkspaceTransform(
      scale: canvasController.zoomScale,
      contentOffset: canvasController.contentOffset)

    return ZStack {
      WorkspaceElementVisualLayer(
        elements: elementSession.orderedElements,
        noteID: page.noteID,
        pageID: page.id,
        attachments: attachments,
        transform: transform,
        onImageAspectRatio: { elementID, aspectRatio in
          elementSession.updateImageAspectRatio(aspectRatio, for: elementID)
        })

      InfiniteCanvasView(
        drawing: session.drawing,
        drawsWithFinger: drawsWithFinger,
        isDrawingEnabled: interactionMode == .draw,
        canvasController: canvasController,
        toolPickerController: toolPickerController,
        onDrawingChanged: session.drawingDidChange,
        onDrawingChangeCommitted: session.recordDrawingChange)

      if interactionMode == .arrange {
        WorkspaceElementInteractionLayer(
          session: elementSession,
          transform: transform,
          onFocus: onFocus,
          onActivate: onElementActivate)
      }
    }
    .accessibilityIdentifier("infinite-canvas")
    .accessibilityValue(
      session.drawing.strokes.count == 1
        ? "1 stroke" : "\(session.drawing.strokes.count) strokes")
  }
}

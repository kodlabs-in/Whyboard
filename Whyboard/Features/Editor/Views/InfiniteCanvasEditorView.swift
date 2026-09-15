import Foundation
import SwiftData
import SwiftUI
import UIKit

struct InfiniteCanvasEditorView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.scenePhase) private var scenePhase
  @Query private var pages: [Page]

  @AppStorage("drawWithFinger", store: AppPreferences.store) private var drawsWithFinger = false
  @AppStorage(NotePaperStyle.defaultStorageKey, store: AppPreferences.store)
  private var defaultPaperStyleRawValue = NotePaperStyle.defaultStyle.rawValue
  @State private var editorController: EditorController
  @State private var canvasController: InfiniteCanvasController
  @State private var toolPickerController = ToolPickerController()
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
    _editorController = State(
      initialValue: EditorController(note: note, drawingRepository: drawingRepository))
    _canvasController = State(
      initialValue: InfiniteCanvasController(
        initialViewport: InfiniteCanvasViewport(storedIn: note)))
  }

  private var page: Page? {
    PageOrdering.ordered(pages).first
  }

  private var resolvedPaperStyle: NotePaperStyle {
    note.paperStyle.resolved(defaultRawValue: defaultPaperStyleRawValue)
  }

  var body: some View {
    canvasContent
      .background(WhyboardTheme.paperColor(for: resolvedPaperStyle))
      .overlay(alignment: .bottomLeading) { navigationHint }
      .navigationTitle(note.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(WhyboardTheme.chromeBackground, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .toolbar { editorToolbar }
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
      let session = editorController.session(for: page, generatesPreview: false)
      InfiniteCanvasSurface(
        page: page,
        session: session,
        paperColor: UIColor(WhyboardTheme.paperColor(for: resolvedPaperStyle)),
        drawsWithFinger: drawsWithFinger,
        canvasController: canvasController,
        toolPickerController: toolPickerController)
    } else {
      ProgressView("Preparing canvas")
        .tint(WhyboardTheme.accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private var navigationHint: some View {
    Label("Pinch to zoom • Drag with two fingers to move", systemImage: "hand.draw")
      .font(.caption.weight(.medium))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(.regularMaterial, in: Capsule())
      .padding(16)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }

  @ToolbarContentBuilder
  private var editorToolbar: some ToolbarContent {
    ToolbarItem(placement: .topBarLeading) {
      EditorSaveStatusView(status: editorController.saveStatus)
    }

    ToolbarItemGroup(placement: .primaryAction) {
      Button("Undo", systemImage: "arrow.uturn.backward", action: toolPickerController.undo)
        .keyboardShortcut("z", modifiers: .command)
        .disabled(!toolPickerController.canUndo)

      Button("Redo", systemImage: "arrow.uturn.forward", action: toolPickerController.redo)
        .keyboardShortcut("z", modifiers: [.command, .shift])
        .disabled(!toolPickerController.canRedo)

      Button("Zoom Out", systemImage: "minus.magnifyingglass", action: canvasController.zoomOut)
        .accessibilityIdentifier("canvas-zoom-out")

      Text(canvasController.zoomPercentage)
        .font(.caption.monospacedDigit())
        .frame(minWidth: 42)
        .accessibilityIdentifier("canvas-zoom-percentage")

      Button("Zoom In", systemImage: "plus.magnifyingglass", action: canvasController.zoomIn)
        .accessibilityIdentifier("canvas-zoom-in")

      Button("Reset View", systemImage: "scope", action: canvasController.resetView)

      NoteOptionsMenu(
        paperStyle: paperStyleSelection,
        drawsWithFinger: $drawsWithFinger,
        onRename: presentRename)
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
    note.lastOpenedAt = Date()

    if pages.isEmpty {
      _ = editorController.appendPage(pages: pages, context: modelContext)
    } else {
      try? modelContext.save()
    }
  }

  private func saveAndClose() {
    canvasController.persistCurrentViewport()
    Task { await editorController.flushAll() }
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
  let paperColor: UIColor
  let drawsWithFinger: Bool
  let canvasController: InfiniteCanvasController
  let toolPickerController: ToolPickerController

  var body: some View {
    Group {
      if session.isLoaded {
        InfiniteCanvasView(
          drawing: session.drawing,
          paperColor: paperColor,
          drawsWithFinger: drawsWithFinger,
          canvasController: canvasController,
          toolPickerController: toolPickerController,
          onDrawingChanged: session.drawingDidChange
        )
        .accessibilityIdentifier("infinite-canvas")
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
    .task(id: page.id) { await session.loadIfNeeded() }
  }
}

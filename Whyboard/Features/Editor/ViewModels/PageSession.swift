import Foundation
import Observation
import PencilKit

enum PageSaveState: Equatable {
  case loading
  case clean
  case dirty
  case saving
  case failed(String)
}

@Observable
final class PageSession {
  let page: Page
  let undoHistory: EditorUndoHistory
  private(set) var drawing = PKDrawing()
  private(set) var drawingRevision = 0
  private var committedDrawingData = PKDrawing().dataRepresentation()
  private(set) var state = PageSaveState.loading {
    didSet { onStateChange() }
  }

  private let note: Note
  private let drawingRepository: DrawingRepository
  private let generatesPreview: Bool
  private let saveMetadata: () throws -> Void
  private let onStateChange: () -> Void
  private var hasLoaded = false
  private var isCancelled = false
  private var changeSequence = 0
  private var persistedSequence = 0
  private var debounceTask: Task<Void, Never>?
  private var persistenceTask: Task<Void, Never>?
  private var previewTask: Task<Void, Never>?

  init(
    page: Page,
    note: Note,
    drawingRepository: DrawingRepository,
    undoHistory: EditorUndoHistory = EditorUndoHistory(),
    generatesPreview: Bool = true,
    saveMetadata: @escaping () throws -> Void,
    onStateChange: @escaping () -> Void
  ) {
    self.page = page
    self.note = note
    self.drawingRepository = drawingRepository
    self.undoHistory = undoHistory
    self.generatesPreview = generatesPreview
    self.saveMetadata = saveMetadata
    self.onStateChange = onStateChange
  }

  var isLoaded: Bool { hasLoaded }

  func loadIfNeeded() async {
    guard !hasLoaded, !isCancelled else { return }
    state = .loading

    do {
      drawing = try await drawingRepository.load(pageID: page.id, noteID: note.id)
      committedDrawingData = drawing.dataRepresentation()
      hasLoaded = true
      state = .clean
    } catch {
      state = .failed(error.localizedDescription)
    }
  }

  func recordDrawingChange(to currentDrawing: PKDrawing, on canvasView: PKCanvasView? = nil) {
    let previousData = committedDrawingData
    let currentData = currentDrawing.dataRepresentation()
    committedDrawingData = currentData
    guard previousData != currentData else { return }
    undoHistory.record(
      scope: page.id,
      estimatedByteCost: combinedByteCount(previousData.count, currentData.count),
      undo: { [weak self, weak canvasView] in
        guard let self else { return false }
        return await applyHistoryDrawing(
          previousData,
          replacing: currentData,
          on: canvasView,
          undoing: true)
      },
      redo: { [weak self, weak canvasView] in
        guard let self else { return false }
        return await applyHistoryDrawing(
          currentData,
          replacing: previousData,
          on: canvasView,
          undoing: false)
      })
  }

  @discardableResult
  func flush() async -> Bool {
    debounceTask?.cancel()
    debounceTask = nil
    guard hasLoaded, !isCancelled else { return true }
    guard persistedSequence < changeSequence else {
      state = .clean
      await previewTask?.value
      return true
    }

    let task = beginPersistence()
    await task.value
    await previewTask?.value
    return persistedSequence == changeSequence && state == .clean
  }

  func cancel() {
    isCancelled = true
    debounceTask?.cancel()
    debounceTask = nil
    persistenceTask?.cancel()
    previewTask?.cancel()
  }

  private func applyHistoryDrawing(
    _ targetData: Data,
    replacing expectedData: Data,
    on canvasView: PKCanvasView?,
    undoing: Bool
  ) async -> Bool {
    if let canvasView, canvasView.window != nil {
      if canvasView.drawing.dataRepresentation() == expectedData {
        if let manager = canvasView.undoManager {
          if undoing ? manager.canUndo : manager.canRedo {
            if undoing { manager.undo() } else { manager.redo() }
          }
          if canvasView.drawing.dataRepresentation() == targetData {
            drawingDidChange(canvasView.drawing)
            committedDrawingData = targetData
            return true
          }
        }
      }
    }

    // Restore the snapshot when the canvas or its native undo action is unavailable.
    guard let targetDrawing = try? PKDrawing(data: targetData) else { return false }
    let didRestore = await restoreHistoryDrawing(targetDrawing)
    if didRestore, let canvasView, canvasView.window != nil {
      canvasView.undoManager?.removeAllActions()
    }
    return didRestore
  }

  private func restoreHistoryDrawing(_ targetDrawing: PKDrawing) async -> Bool {
    guard hasLoaded, !isCancelled else { return false }
    guard await flush() else { return false }

    let previousDrawing = drawing
    let previousData = committedDrawingData
    let previousChangeSequence = changeSequence
    let previousPersistedSequence = persistedSequence
    drawing = targetDrawing
    committedDrawingData = targetDrawing.dataRepresentation()
    drawingRevision += 1
    changeSequence += 1
    state = .dirty

    guard !(await flush()) else { return true }

    let failedState = state
    drawing = previousDrawing
    committedDrawingData = previousData
    drawingRevision += 1
    do {
      try await drawingRepository.save(
        previousDrawing,
        pageID: page.id,
        noteID: note.id)
      changeSequence = previousChangeSequence
      persistedSequence = previousPersistedSequence
      state = failedState
    } catch {
      state = .failed(error.localizedDescription)
    }
    return false
  }

  private func scheduleSave() {
    guard persistenceTask == nil else { return }
    debounceTask?.cancel()

    debounceTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .milliseconds(750))
      } catch {
        return
      }
      await self?.runScheduledPersistence()
    }
  }

  private func runScheduledPersistence() async {
    debounceTask = nil
    let task = beginPersistence()
    await task.value
  }

  private func beginPersistence() -> Task<Void, Never> {
    if let persistenceTask {
      return persistenceTask
    }

    let task = Task { [weak self] in
      guard let self else { return }
      await persistenceLoop()
    }
    persistenceTask = task
    return task
  }

  private func persistenceLoop() async {
    while persistedSequence < changeSequence, !isCancelled, !Task.isCancelled {
      let snapshot = drawing
      let sequence = changeSequence
      state = .saving

      do {
        try await drawingRepository.save(snapshot, pageID: page.id, noteID: note.id)
        guard !isCancelled else { break }
        let revision = try finishSave()
        persistedSequence = sequence
        schedulePreview(snapshot, revision: revision)
      } catch {
        state = .failed(error.localizedDescription)
        break
      }
    }

    persistenceTask = nil
    if !isCancelled, persistedSequence == changeSequence {
      state = .clean
    }
  }

  private func finishSave() throws -> Int64 {
    let now = Date()
    let previousRevision = page.contentRevision
    let previousPageUpdate = page.updatedAt
    let previousNoteUpdate = note.updatedAt
    page.contentRevision += 1
    page.updatedAt = now
    note.updatedAt = now

    do {
      try saveMetadata()
      return page.contentRevision
    } catch {
      page.contentRevision = previousRevision
      page.updatedAt = previousPageUpdate
      note.updatedAt = previousNoteUpdate
      throw error
    }
  }

  private func schedulePreview(_ drawing: PKDrawing, revision: Int64) {
    guard generatesPreview else { return }
    let pageID = page.id
    let noteID = note.id
    let elements = WorkspaceElementCoding.decode(page.workspaceElementsData)
    let layout = PagePreviewLayout(note: note)
    let previews = drawingRepository.previews
    previewTask?.cancel()
    previewTask = Task {
      do {
        try Task.checkCancellation()
        try await previews.store(
          drawing: drawing,
          elements: elements,
          layout: layout,
          paperStyle: note.paperStyle,
          background: ImportedPDFBackground(page: page),
          pageID: pageID,
          noteID: noteID,
          revision: revision)
      } catch {
        return
      }
    }
  }

}

extension PageSession {
  func drawingDidChange(_ drawing: PKDrawing) {
    guard hasLoaded, !isCancelled else { return }
    self.drawing = drawing
    changeSequence += 1
    state = .dirty
    scheduleSave()
  }
}

private extension PageSession {
  func combinedByteCount(_ first: Int, _ second: Int) -> Int {
    let (sum, overflow) = first.addingReportingOverflow(second)
    return overflow ? .max : sum
  }
}

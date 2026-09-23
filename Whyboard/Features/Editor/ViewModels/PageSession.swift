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
      hasLoaded = true
      state = .clean
    } catch {
      state = .failed(error.localizedDescription)
    }
  }

  func drawingDidChange(_ drawing: PKDrawing) {
    guard hasLoaded, !isCancelled else { return }
    self.drawing = drawing
    changeSequence += 1
    state = .dirty
    scheduleSave()
  }

  func recordDrawingChange(from previousDrawing: PKDrawing, to currentDrawing: PKDrawing) {
    guard previousDrawing != currentDrawing else { return }
    undoHistory.record(
      scope: page.id,
      estimatedByteCost: estimatedByteCost(previousDrawing, currentDrawing),
      undo: { [weak self] in
        guard let self else { return false }
        return await applyHistoryDrawing(previousDrawing)
      },
      redo: { [weak self] in
        guard let self else { return false }
        return await applyHistoryDrawing(currentDrawing)
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

  private func applyHistoryDrawing(_ targetDrawing: PKDrawing) async -> Bool {
    guard hasLoaded, !isCancelled else { return false }
    guard await flush() else { return false }

    let previousDrawing = drawing
    let previousChangeSequence = changeSequence
    let previousPersistedSequence = persistedSequence
    drawing = targetDrawing
    changeSequence += 1
    state = .dirty

    guard !(await flush()) else { return true }

    let failedState = state
    drawing = previousDrawing
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

  private func estimatedByteCost(_ first: PKDrawing, _ second: PKDrawing) -> Int {
    let (sum, overflow) = first.dataRepresentation().count.addingReportingOverflow(
      second.dataRepresentation().count)
    return overflow ? .max : sum
  }
}

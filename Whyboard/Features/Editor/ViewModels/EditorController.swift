import Foundation
import Observation
import PencilKit
import SwiftData
import SwiftUI

enum EditorSaveStatus: Equatable {
  case saved
  case unsaved
  case saving
  case failed(String)
}

@Observable
final class EditorController {
  let undoHistory: EditorUndoHistory
  private(set) var livePageIDs: Set<UUID> = []
  private(set) var activePageID: UUID?
  private(set) var saveStatus = EditorSaveStatus.saved
  var errorMessage: String?

  private let note: Note
  private let drawingRepository: DrawingRepository
  private var visiblePageIDs: Set<UUID> = []
  private var sessions: [UUID: PageSession] = [:]
  private var elementSessions: [UUID: ElementSession] = [:]
  private var previewTasks: [UUID: Task<Void, Never>] = [:]
  private var saveMetadata: (() throws -> Void)?
  private var pendingSaveRegistration: PendingSaveRegistration?
  private var closeRequested = false

  init(
    note: Note,
    drawingRepository: DrawingRepository,
    undoHistory: EditorUndoHistory = EditorUndoHistory()
  ) {
    self.note = note
    self.drawingRepository = drawingRepository
    self.undoHistory = undoHistory
    undoHistory.setDiscardHandler { [weak self] scopes in
      self?.collectUnusedAttachments(for: scopes)
    }
  }

  func configure(saveMetadata: @escaping () throws -> Void) {
    self.saveMetadata = saveMetadata
    closeRequested = false
    guard pendingSaveRegistration == nil else { return }
    pendingSaveRegistration = drawingRepository.pendingSaves.register(
      noteID: note.id,
      flusher: { [self] in
        await flushPendingSaves()
      })
  }

  func session(for page: Page, generatesPreview: Bool = true) -> PageSession {
    if let session = sessions[page.id] {
      return session
    }

    let session = PageSession(
      page: page,
      note: note,
      drawingRepository: drawingRepository,
      undoHistory: undoHistory,
      generatesPreview: generatesPreview,
      saveMetadata: { [weak self] in try self?.saveMetadata?() },
      onStateChange: { [weak self] in self?.refreshSaveStatus() })
    sessions[page.id] = session
    return session
  }

  func elementSession(for page: Page, canvasSize: CGSize) -> ElementSession {
    if let session = elementSessions[page.id] {
      return session
    }

    let session = ElementSession(
      page: page,
      note: note,
      canvasSize: canvasSize,
      undoHistory: undoHistory,
      saveMetadata: { [weak self] in try self?.saveMetadata?() },
      onError: { [weak self] message in self?.errorMessage = message },
      onPreviewInvalidated: { [weak self] elements, revision in
        self?.schedulePreview(
          page: page,
          elements: elements,
          revision: revision)
      })
    elementSessions[page.id] = session
    return session
  }

  func pageAppeared(_ pageID: UUID, orderedPageIDs: [UUID]) {
    visiblePageIDs.insert(pageID)
    activePageID = activePageID ?? pageID
    updateLiveWindow(orderedPageIDs: orderedPageIDs)
  }

  func pageDisappeared(_ pageID: UUID, orderedPageIDs: [UUID]) {
    visiblePageIDs.remove(pageID)
    updateLiveWindow(orderedPageIDs: orderedPageIDs)
  }

  func focus(_ pageID: UUID) {
    activePageID = pageID
  }

  func updateActivePage(
    scrollOffset: Double,
    viewportHeight: Double,
    pageHeight: Double,
    orderedPageIDs: [UUID]
  ) {
    guard !orderedPageIDs.isEmpty, pageHeight > 0, viewportHeight > 0 else { return }
    let pageSpacing = 28.0
    let verticalPadding = 28.0
    let viewportCenter = scrollOffset + viewportHeight / 2
    let firstPageCenter = verticalPadding + pageHeight / 2
    let rawIndex = ((viewportCenter - firstPageCenter) / (pageHeight + pageSpacing)).rounded()
    let index = min(max(Int(rawIndex), 0), orderedPageIDs.count - 1)
    activePageID = orderedPageIDs[index]
  }

  func isPageLoaded(_ pageID: UUID) -> Bool {
    sessions[pageID]?.isLoaded == true
  }

  func reconcile(pages: [Page]) {
    let existingIDs = Set(pages.map(\.id))
    let removedIDs = Set(sessions.keys).subtracting(existingIDs)
    for pageID in removedIDs {
      sessions[pageID]?.cancel()
      sessions[pageID] = nil
      elementSessions[pageID] = nil
      previewTasks[pageID]?.cancel()
      previewTasks[pageID] = nil
      undoHistory.removeCommands(scope: pageID)
    }
  }

  @discardableResult
  func flushAll() async -> Bool {
    var didSaveEverything = true
    for session in sessions.values {
      didSaveEverything = await session.flush() && didSaveEverything
    }
    return didSaveEverything
  }

  @discardableResult
  func close() async -> Bool {
    closeRequested = true
    return await flushPendingSaves()
  }

  func handleMemoryWarning() {
    let removableIDs = Set(sessions.keys).subtracting(visiblePageIDs)
    livePageIDs = visiblePageIDs

    Task { [weak self] in
      guard let self else { return }
      for pageID in removableIDs {
        await releaseSessionIfPossible(pageID)
      }
      await drawingRepository.previews.clearMemoryCache()
      refreshSaveStatus()
    }
  }

  func appendPage(pages: [Page], context: ModelContext) -> UUID {
    let orderedPages = PageOrdering.ordered(pages)
    let page = Page(noteID: note.id, sortOrder: orderedPages.count)
    context.insert(page)
    note.updatedAt = Date()
    saveContext(context)
    return page.id
  }

  func insertPage(
    relativeTo anchor: Page,
    after: Bool,
    pages: [Page],
    context: ModelContext
  ) -> UUID {
    var orderedPages = PageOrdering.ordered(pages)
    let anchorIndex = orderedPages.firstIndex { $0.id == anchor.id } ?? orderedPages.count - 1
    let insertionIndex = min(orderedPages.count, anchorIndex + (after ? 1 : 0))
    let page = Page(noteID: note.id, sortOrder: insertionIndex)
    orderedPages.insert(page, at: insertionIndex)
    PageOrdering.renumber(orderedPages)
    context.insert(page)
    note.updatedAt = Date()
    saveContext(context)
    return page.id
  }

  @discardableResult
  func deletePage(_ page: Page, pages: [Page], context: ModelContext) async -> Bool {
    guard pages.count > 1 else {
      errorMessage = "A note must always contain at least one page."
      return false
    }

    let pageID = page.id
    let noteID = note.id
    let orderedPages = PageOrdering.ordered(pages)
    let deletedIndex = orderedPages.firstIndex { $0.id == pageID } ?? 0
    if let session = sessions[pageID], !(await session.flush()) {
      errorMessage = "Whyboard could not save this page before deleting it. Please try again."
      return false
    }

    context.delete(page)
    let remainingPages = orderedPages.filter { $0.id != pageID }
    PageOrdering.renumber(remainingPages)
    note.updatedAt = Date()
    guard saveContext(context) else {
      context.rollback()
      return false
    }

    sessions[pageID]?.cancel()
    sessions[pageID] = nil
    elementSessions[pageID] = nil
    previewTasks[pageID]?.cancel()
    previewTasks[pageID] = nil
    undoHistory.removeCommands(scope: pageID)
    if activePageID == pageID {
      let adjacentIndex = min(deletedIndex, remainingPages.count - 1)
      activePageID = remainingPages[adjacentIndex].id
    }
    await drawingRepository.deletePage(pageID: pageID, noteID: noteID)
    return true
  }

  func movePages(
    from offsets: IndexSet,
    to destination: Int,
    pages: [Page],
    context: ModelContext
  ) {
    var orderedPages = PageOrdering.ordered(pages)
    orderedPages.move(fromOffsets: offsets, toOffset: destination)
    PageOrdering.renumber(orderedPages)
    note.updatedAt = Date()
    saveContext(context)
  }
}

private extension EditorController {
  private func updateLiveWindow(orderedPageIDs: [UUID]) {
    let nextIDs = PageWindow.livePageIDs(
      orderedPageIDs: orderedPageIDs,
      visiblePageIDs: visiblePageIDs)
    let leavingIDs = livePageIDs.subtracting(nextIDs)
    livePageIDs = nextIDs

    Task { [weak self] in
      guard let self else { return }
      for pageID in leavingIDs {
        await releaseSessionIfPossible(pageID)
      }
    }
  }

  private func releaseSessionIfPossible(_ pageID: UUID) async {
    guard let session = sessions[pageID] else { return }
    let canRelease = await session.flush()
    guard canRelease, !livePageIDs.contains(pageID) else { return }
    undoHistory.removeCommands(scope: pageID)
    session.cancel()
    sessions[pageID] = nil
    elementSessions[pageID] = nil
    previewTasks[pageID]?.cancel()
    previewTasks[pageID] = nil
  }

  private func refreshSaveStatus() {
    let states = sessions.values.map(\.state)
    if let message = states.compactMap(failureMessage).first {
      saveStatus = .failed(message)
    } else if states.contains(.saving) {
      saveStatus = .saving
    } else if states.contains(.dirty) {
      saveStatus = .unsaved
    } else {
      saveStatus = .saved
    }
  }

  private func flushPendingSaves() async -> Bool {
    let didFlush = await flushAll()
    if didFlush, closeRequested {
      let pageIDs = Set(elementSessions.keys)
      undoHistory.removeAllCommands()
      await collectUnusedAttachmentsNow(for: pageIDs)
      if let pendingSaveRegistration {
        drawingRepository.pendingSaves.unregister(pendingSaveRegistration)
        self.pendingSaveRegistration = nil
      }
    }
    return didFlush
  }

  private func collectUnusedAttachments(for pageIDs: Set<UUID>) {
    for pageID in pageIDs {
      let currentFilenames = elementSessions[pageID]?.referencedAttachmentFilenames ?? []
      let retainedFilenames = undoHistory.retainedAttachmentFilenames(scope: pageID)
      let filenamesToKeep = currentFilenames.union(retainedFilenames)
      let noteID = note.id
      let attachments = drawingRepository.attachments
      Task {
        await attachments.removeUnreferencedFiles(
          noteID: noteID,
          pageID: pageID,
          keeping: filenamesToKeep)
      }
    }
  }

  private func collectUnusedAttachmentsNow(for pageIDs: Set<UUID>) async {
    for pageID in pageIDs {
      let currentFilenames = elementSessions[pageID]?.referencedAttachmentFilenames ?? []
      let retainedFilenames = undoHistory.retainedAttachmentFilenames(scope: pageID)
      await drawingRepository.attachments.removeUnreferencedFiles(
        noteID: note.id,
        pageID: pageID,
        keeping: currentFilenames.union(retainedFilenames))
    }
  }

  private func failureMessage(_ state: PageSaveState) -> String? {
    guard case .failed(let message) = state else { return nil }
    return message
  }

  @discardableResult
  private func saveContext(_ context: ModelContext) -> Bool {
    do {
      if let saveMetadata {
        try saveMetadata()
      } else {
        try context.save()
      }
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }
}

private extension EditorController {
  private func schedulePreview(
    page: Page,
    elements: [WorkspaceElement],
    revision: Int64
  ) {
    let currentDrawing = sessions[page.id]?.isLoaded == true ? sessions[page.id]?.drawing : nil
    let pageID = page.id
    let noteID = note.id
    let layout = PagePreviewLayout(note: note)
    let drawingRepository = drawingRepository

    previewTasks[pageID]?.cancel()
    previewTasks[pageID] = Task {
      guard !Task.isCancelled else { return }
      guard
        let drawing = await previewDrawing(
          current: currentDrawing,
          pageID: pageID,
          noteID: noteID)
      else { return }
      guard !Task.isCancelled else { return }
      try? await drawingRepository.previews.store(
        drawing: drawing,
        elements: elements,
        layout: layout,
        paperStyle: note.paperStyle,
        background: ImportedPDFBackground(page: page),
        pageID: pageID,
        noteID: noteID,
        revision: revision)
    }
  }

  private func previewDrawing(
    current: PKDrawing?,
    pageID: UUID,
    noteID: UUID
  ) async -> PKDrawing? {
    if let current { return current }
    return try? await drawingRepository.load(pageID: pageID, noteID: noteID)
  }
}

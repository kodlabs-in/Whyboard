import Foundation
import Observation
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
  private(set) var livePageIDs: Set<UUID> = []
  private(set) var activePageID: UUID?
  private(set) var saveStatus = EditorSaveStatus.saved
  var errorMessage: String?

  private let note: Note
  private let drawingRepository: DrawingRepository
  private var visiblePageIDs: Set<UUID> = []
  private var sessions: [UUID: PageSession] = [:]
  private var elementSessions: [UUID: ElementSession] = [:]
  private var saveMetadata: (() throws -> Void)?

  init(note: Note, drawingRepository: DrawingRepository) {
    self.note = note
    self.drawingRepository = drawingRepository
  }

  func configure(saveMetadata: @escaping () throws -> Void) {
    self.saveMetadata = saveMetadata
  }

  func session(for page: Page, generatesPreview: Bool = true) -> PageSession {
    if let session = sessions[page.id] {
      return session
    }

    let session = PageSession(
      page: page,
      note: note,
      drawingRepository: drawingRepository,
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
      saveMetadata: { [weak self] in try self?.saveMetadata?() },
      onError: { [weak self] message in self?.errorMessage = message })
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

  func reconcile(pages: [Page]) {
    let existingIDs = Set(pages.map(\.id))
    let removedIDs = Set(sessions.keys).subtracting(existingIDs)
    for pageID in removedIDs {
      sessions[pageID]?.cancel()
      sessions[pageID] = nil
      elementSessions[pageID] = nil
    }
  }

  func flushAll() async {
    for session in sessions.values {
      await session.flush()
    }
  }

  func handleMemoryWarning() {
    let removableIDs = Set(sessions.keys).subtracting(visiblePageIDs)
    livePageIDs = visiblePageIDs

    Task { [weak self] in
      guard let self else { return }
      for pageID in removableIDs {
        await releaseSessionIfPossible(pageID)
      }
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

  func deletePage(_ page: Page, pages: [Page], context: ModelContext) {
    guard pages.count > 1 else {
      errorMessage = "A note must always contain at least one page."
      return
    }

    sessions[page.id]?.cancel()
    sessions[page.id] = nil
    elementSessions[page.id] = nil
    context.delete(page)
    PageOrdering.renumber(PageOrdering.ordered(pages.filter { $0.id != page.id }))
    note.updatedAt = Date()
    saveContext(context)

    Task { await drawingRepository.deletePage(pageID: page.id, noteID: note.id) }
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
    session.cancel()
    sessions[pageID] = nil
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

  private func failureMessage(_ state: PageSaveState) -> String? {
    guard case .failed(let message) = state else { return nil }
    return message
  }

  private func saveContext(_ context: ModelContext) {
    do {
      try context.save()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

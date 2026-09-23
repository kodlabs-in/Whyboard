import CoreGraphics
import Foundation
import PencilKit
import Testing
import UIKit

@testable import Whyboard

private enum InkHistoryTestError: Error {
  case metadataSaveFailed
}

@MainActor
struct EditorStorageLifecycleTests {
  @Test func deletedAttachmentRemainsUndoableUntilEditorCloseThenIsReclaimed() async throws {
    let directories = try AppDirectories.makeForTesting()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let note = Note(folderID: UUID())
    let page = Page(noteID: note.id, sortOrder: 0)
    let repository = DrawingRepository(directories: directories)
    let controller = EditorController(note: note, drawingRepository: repository)
    controller.configure(saveMetadata: {})
    let source = directories.root.appending(path: "attachment.data")
    try Data("fixture".utf8).write(to: source)
    let filename = try await repository.attachments.importFile(
      at: source,
      noteID: note.id,
      pageID: page.id)
    let fileURL = repository.attachments.fileURL(
      noteID: note.id,
      pageID: page.id,
      filename: filename)
    let session = controller.elementSession(for: page, canvasSize: CanonicalPage.size)

    #expect(
      session.addImage(
        ImportedImageAsset(filename: filename, displayName: "Fixture", aspectRatio: 1),
        at: CGPoint(x: 320, y: 480)))
    _ = session.deleteSelected()
    #expect(FileManager.default.fileExists(atPath: fileURL.path))

    #expect(await controller.undoHistory.undo())
    #expect(session.elements.first?.assetFilename == filename)
    #expect(FileManager.default.fileExists(atPath: fileURL.path))
    #expect(await controller.undoHistory.redo())
    #expect(session.elements.isEmpty)
    #expect(FileManager.default.fileExists(atPath: fileURL.path))

    #expect(await controller.close())
    await waitUntil { !FileManager.default.fileExists(atPath: fileURL.path) }
    #expect(!FileManager.default.fileExists(atPath: fileURL.path))
  }

  @Test func historyEvictionReclaimsAnAttachmentNoLongerReferencedByThePage() async throws {
    let directories = try AppDirectories.makeForTesting()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let note = Note(folderID: UUID())
    let page = Page(noteID: note.id, sortOrder: 0)
    let repository = DrawingRepository(directories: directories)
    let history = EditorUndoHistory(limit: 1)
    let controller = EditorController(
      note: note,
      drawingRepository: repository,
      undoHistory: history)
    let source = directories.root.appending(path: "eviction.data")
    try Data("fixture".utf8).write(to: source)
    let filename = try await repository.attachments.importFile(
      at: source,
      noteID: note.id,
      pageID: page.id)
    let fileURL = repository.attachments.fileURL(
      noteID: note.id,
      pageID: page.id,
      filename: filename)
    let session = controller.elementSession(for: page, canvasSize: CanonicalPage.size)

    #expect(
      session.addImage(
        ImportedImageAsset(filename: filename, displayName: "Fixture", aspectRatio: 1),
        at: CGPoint(x: 320, y: 480)))
    _ = session.deleteSelected()
    #expect(FileManager.default.fileExists(atPath: fileURL.path))

    _ = session.addShape(.circle, at: CGPoint(x: 320, y: 480))
    await waitUntil { !FileManager.default.fileExists(atPath: fileURL.path) }
    #expect(!FileManager.default.fileExists(atPath: fileURL.path))
  }

  @Test func inkHistorySurvivesCanvasViewRecreation() async throws {
    let directories = try AppDirectories.makeForTesting()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let note = Note(folderID: UUID())
    let page = Page(noteID: note.id, sortOrder: 0)
    let repository = DrawingRepository(directories: directories)
    let history = EditorUndoHistory()
    let session = PageSession(
      page: page,
      note: note,
      drawingRepository: repository,
      undoHistory: history,
      generatesPreview: false,
      saveMetadata: {},
      onStateChange: {})
    await session.loadIfNeeded()
    let blankDrawing = session.drawing
    let inkDrawing = makeInkDrawing()
    session.drawingDidChange(inkDrawing)
    session.recordDrawingChange(from: blankDrawing, to: inkDrawing)

    #expect(await history.undo())
    let reopenedAfterUndo = PageSession(
      page: page,
      note: note,
      drawingRepository: repository,
      generatesPreview: false,
      saveMetadata: {},
      onStateChange: {})
    await reopenedAfterUndo.loadIfNeeded()
    #expect(reopenedAfterUndo.drawing.strokes.isEmpty)

    #expect(await history.redo())
    let reopenedAfterRedo = PageSession(
      page: page,
      note: note,
      drawingRepository: repository,
      generatesPreview: false,
      saveMetadata: {},
      onStateChange: {})
    await reopenedAfterRedo.loadIfNeeded()
    #expect(reopenedAfterRedo.drawing.strokes.count == 1)
  }

  @Test func failedInkUndoRemainsAvailableAndKeepsTheCurrentDrawing() async throws {
    let directories = try AppDirectories.makeForTesting()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let note = Note(folderID: UUID())
    let page = Page(noteID: note.id, sortOrder: 0)
    let repository = DrawingRepository(directories: directories)
    let history = EditorUndoHistory()
    var metadataCanSave = true
    let session = PageSession(
      page: page,
      note: note,
      drawingRepository: repository,
      undoHistory: history,
      generatesPreview: false,
      saveMetadata: {
        if !metadataCanSave { throw InkHistoryTestError.metadataSaveFailed }
      },
      onStateChange: {})
    await session.loadIfNeeded()
    let blankDrawing = session.drawing
    let inkDrawing = makeInkDrawing()
    session.drawingDidChange(inkDrawing)
    session.recordDrawingChange(from: blankDrawing, to: inkDrawing)
    #expect(await session.flush())
    metadataCanSave = false

    #expect(!(await history.undo()))
    #expect(session.drawing == inkDrawing)
    #expect(history.canUndo)
    #expect(!history.canRedo)
    #expect(try await repository.load(pageID: page.id, noteID: note.id) == inkDrawing)

    metadataCanSave = true
    #expect(await history.undo())
    #expect(session.drawing.strokes.isEmpty)
    #expect(history.canRedo)
  }

  private func makeInkDrawing() -> PKDrawing {
    let points = [
      PKStrokePoint(
        location: CGPoint(x: 40, y: 40),
        timeOffset: 0,
        size: CGSize(width: 4, height: 4),
        opacity: 1,
        force: 0.5,
        azimuth: 0,
        altitude: .pi / 2),
      PKStrokePoint(
        location: CGPoint(x: 120, y: 120),
        timeOffset: 0.2,
        size: CGSize(width: 4, height: 4),
        opacity: 1,
        force: 0.5,
        azimuth: 0,
        altitude: .pi / 2),
    ]
    let path = PKStrokePath(controlPoints: points, creationDate: .now)
    return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)])
  }

  private func waitUntil(
    timeout: Duration = .seconds(1),
    condition: @escaping () -> Bool
  ) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition(), clock.now < deadline {
      try? await Task.sleep(for: .milliseconds(10))
    }
  }
}

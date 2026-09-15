import CoreGraphics
import Foundation
import PencilKit
import Testing

@testable import Whyboard

@MainActor
struct InfiniteCanvasTests {
  @Test func zoomScaleIsClampedToSupportedRange() {
    #expect(
      InfiniteCanvasMetrics.clampedZoomScale(0.05)
        == InfiniteCanvasMetrics.minimumZoomScale)
    #expect(
      InfiniteCanvasMetrics.clampedZoomScale(8)
        == InfiniteCanvasMetrics.maximumZoomScale)
    #expect(InfiniteCanvasMetrics.clampedZoomScale(1.25) == 1.25)
  }

  @Test func viewportRoundTripsThroughNoteMetadata() throws {
    let note = Note(folderID: UUID(), kind: .infiniteCanvas)
    note.canvasOffsetX = 750
    note.canvasOffsetY = 1_250
    note.canvasZoomScale = 1.5

    let viewport = try #require(InfiniteCanvasViewport(storedIn: note))

    #expect(viewport.contentOffset == CGPoint(x: 750, y: 1_250))
    #expect(viewport.zoomScale == 1.5)
    #expect(!viewport.differs(from: note))
  }

  @Test func canvasSessionSkipsPagePreviewGeneration() async throws {
    let directories = try AppDirectories.make(isTesting: true)
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let note = Note(folderID: UUID(), kind: .infiniteCanvas)
    let page = Page(noteID: note.id, sortOrder: 0)
    let session = PageSession(
      page: page,
      note: note,
      drawingRepository: DrawingRepository(directories: directories),
      generatesPreview: false,
      saveMetadata: {},
      onStateChange: {})

    await session.loadIfNeeded()
    session.drawingDidChange(PKDrawing())
    let saved = await session.flush()
    let previews = try FileManager.default.contentsOfDirectory(
      at: directories.previews,
      includingPropertiesForKeys: nil)

    #expect(saved)
    #expect(previews.isEmpty)
  }
}

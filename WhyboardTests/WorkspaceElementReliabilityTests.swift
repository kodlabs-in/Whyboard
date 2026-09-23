import CoreGraphics
import Foundation
import Testing

@testable import Whyboard

private enum WorkspaceReliabilityTestError: Error {
  case saveFailed
}

@MainActor
struct WorkspaceElementReliabilityTests {
  @Test func accessibilityResizeUsesGestureMinimumsAndPreservesRequiredAspectRatios() throws {
    let note = Note(folderID: UUID())
    let page = Page(noteID: note.id, sortOrder: 0)
    let session = ElementSession(
      page: page,
      note: note,
      canvasSize: CanonicalPage.size,
      saveMetadata: {},
      onError: { _ in })
    let circleID = session.addShape(.circle, at: CGPoint(x: 320, y: 480))

    session.resize(circleID, by: 0.01)

    let circle = try #require(session.element(withID: circleID))
    #expect(circle.frame.width == 80)
    #expect(circle.frame.height == 80)

    let rectangleID = session.addShape(.rectangle, at: CGPoint(x: 320, y: 480))
    session.resize(rectangleID, by: 0.01)
    let rectangle = try #require(session.element(withID: rectangleID))
    #expect(rectangle.frame.width == 80)
    #expect(rectangle.frame.height == 60)
  }

  @Test func failedImageInsertionReportsThatNoElementWasCommitted() {
    let note = Note(folderID: UUID())
    let page = Page(noteID: note.id, sortOrder: 0)
    let session = ElementSession(
      page: page,
      note: note,
      canvasSize: CanonicalPage.size,
      saveMetadata: { throw WorkspaceReliabilityTestError.saveFailed },
      onError: { _ in })

    let didCommit = session.addImage(
      ImportedImageAsset(filename: "photo.jpg", displayName: "Photo", aspectRatio: 1.5),
      at: CGPoint(x: 300, y: 400))

    #expect(!didCommit)
    #expect(session.elements.isEmpty)
    #expect(page.workspaceElementsData == nil)
    #expect(page.contentRevision == 0)
  }
}

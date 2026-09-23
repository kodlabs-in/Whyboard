import CoreGraphics
import Foundation
import Testing

@testable import Whyboard

@MainActor
struct WorkspaceWorkflowIntegrationTests {
  @Test func compositeShapeEditsPersistWhenTheWorkspaceSessionReopens() throws {
    let directories = try AppDirectories.makeForTesting()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let note = Note(folderID: UUID(), title: "Unit Circle")
    let page = Page(noteID: note.id, sortOrder: 0)
    let insertionPoint = CGPoint(x: 360, y: 480)
    var errors: [String] = []
    let session = ElementSession(
      page: page,
      note: note,
      canvasSize: CanonicalPage.size,
      saveMetadata: {},
      onError: { errors.append($0) })
    let controller = WorkspaceElementEditingController(
      noteID: note.id,
      attachments: AttachmentRepository(directories: directories))
    controller.configure(
      resolveTarget: { _ in
        ElementEditingTarget(
          pageID: page.id,
          session: session,
          insertionPoint: insertionPoint)
      },
      onError: { errors.append($0) })

    controller.addShape(.circle)
    let circleID = try #require(controller.selectedElement?.id)
    controller.addShape(.line)
    let lineID = try #require(controller.selectedElement?.id)
    controller.setSelectedColor(.orange)
    let lineFrame = try #require(session.element(withID: lineID)?.frame)
    session.commitFrame(lineFrame.rotated(by: 90), for: lineID)
    controller.duplicateSelected()
    controller.deleteSelected()

    let reopened = ElementSession(
      page: page,
      note: note,
      canvasSize: CanonicalPage.size,
      saveMetadata: {},
      onError: { errors.append($0) })

    #expect(reopened.elements.map(\.id) == [circleID, lineID])
    #expect(reopened.elements.map(\.shapeKind) == [.circle, .line])
    #expect(reopened.elements.allSatisfy { $0.frame.center == insertionPoint })
    #expect(reopened.element(withID: lineID)?.color == .orange)
    #expect(reopened.element(withID: lineID)?.frame.rotationDegrees == 90)
    #expect(errors.isEmpty)
  }
}

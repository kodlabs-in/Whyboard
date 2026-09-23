import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import Whyboard

@MainActor
struct WorkspaceTextStyleTests {
  @Test func arbitraryPickerColorRoundTrips() throws {
    let color = WorkspaceTextColor(
      Color(red: 0.13, green: 0.47, blue: 0.81, opacity: 0.64))
    #expect(abs(color.red - 0.13) < 0.01)
    #expect(abs(color.green - 0.47) < 0.01)
    #expect(abs(color.blue - 0.81) < 0.01)
    #expect(abs(color.opacity - 0.64) < 0.01)

    let element = WorkspaceElement(
      kind: .text,
      frame: WorkspaceElementFrame(
        center: CGPoint(x: 300, y: 400),
        size: CGSize(width: 300, height: 130)),
      zIndex: 0,
      text: "Color",
      fontSize: 36,
      textColor: color)
    let decoded = WorkspaceElementCoding.decode(try WorkspaceElementCoding.encode([element]))
    #expect(decoded == [element])
  }

  @Test func textStylePersistsAndUndoesAsOneChange() async throws {
    let note = Note(folderID: UUID())
    let page = Page(noteID: note.id, sortOrder: 0)
    let history = EditorUndoHistory()
    let session = ElementSession(
      page: page,
      note: note,
      canvasSize: CanonicalPage.size,
      undoHistory: history,
      saveMetadata: {},
      onError: { _ in })
    let id = session.addText(at: CGPoint(x: 300, y: 400))

    session.updateSelectedText("White title", fontSize: 42, color: .white)
    let styled = try #require(WorkspaceElementCoding.decode(page.workspaceElementsData).first)
    #expect(styled.id == id)
    #expect(styled.text == "White title")
    #expect(styled.resolvedFontSize == 42)
    #expect(styled.textColor == .white)
    #expect(WorkspaceTextColor(Color.white) == .white)

    #expect(await history.undo())
    let previous = try #require(session.selectedElement)
    #expect(previous.text == "")
    #expect(previous.resolvedFontSize == 28)
    #expect(previous.textColor == nil)

    #expect(await history.redo())
    #expect(session.selectedElement == styled)
    session.duplicateSelected()
    #expect(session.selectedElement?.textColor == .white)
    #expect(session.selectedElement?.resolvedFontSize == 42)
  }
}

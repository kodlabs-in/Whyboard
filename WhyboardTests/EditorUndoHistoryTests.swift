import CoreGraphics
import Foundation
import Testing

@testable import Whyboard

@MainActor
struct EditorUndoHistoryTests {
  @Test func workspaceChangesParticipateInTheEditorUndoHistory() async {
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

    let circleID = session.addShape(.circle, at: CGPoint(x: 320, y: 480))
    #expect(history.canUndo)

    await history.undo()
    #expect(session.elements.isEmpty)
    #expect(history.canRedo)

    await history.redo()
    #expect(session.elements.map(\.id) == [circleID])
  }

  @Test func historyRetainsOnlyItsConfiguredNumberOfCommands() async {
    let history = EditorUndoHistory(limit: 2)
    var value = 0

    for nextValue in 1...3 {
      let previousValue = value
      value = nextValue
      history.record(
        scope: UUID(),
        undo: {
          value = previousValue
          return true
        },
        redo: {
          value = nextValue
          return true
        })
    }

    await history.undo()
    await history.undo()
    await history.undo()

    #expect(value == 1)
    #expect(!history.canUndo)
  }

  @Test func failedCommandsRemainOnTheirOriginalStackUntilTheyCommit() async {
    let history = EditorUndoHistory()
    var value = 1
    var undoCanCommit = false
    var redoCanCommit = false
    history.record(
      scope: UUID(),
      undo: {
        guard undoCanCommit else { return false }
        value = 0
        return true
      },
      redo: {
        guard redoCanCommit else { return false }
        value = 1
        return true
      })

    #expect(!(await history.undo()))
    #expect(value == 1)
    #expect(history.canUndo)
    #expect(!history.canRedo)

    undoCanCommit = true
    #expect(await history.undo())
    #expect(value == 0)
    #expect(!history.canUndo)
    #expect(history.canRedo)

    #expect(!(await history.redo()))
    #expect(value == 0)
    #expect(history.canRedo)

    redoCanCommit = true
    #expect(await history.redo())
    #expect(value == 1)
    #expect(history.canUndo)
    #expect(!history.canRedo)
  }

  @Test func historyEvictsCommandsThatExceedItsCombinedByteBudget() async {
    let history = EditorUndoHistory(limit: 10, byteLimit: 10)
    var value = 0

    value = 1
    history.record(
      scope: UUID(),
      estimatedByteCost: 6,
      undo: {
        value = 0
        return true
      },
      redo: {
        value = 1
        return true
      })
    value = 2
    history.record(
      scope: UUID(),
      estimatedByteCost: 6,
      undo: {
        value = 1
        return true
      },
      redo: {
        value = 2
        return true
      })

    #expect(await history.undo())
    #expect(value == 1)
    #expect(!(await history.undo()))
    #expect(!history.canUndo)
  }

  @Test func anOversizedLatestChangeCanStillBeUndone() async {
    let history = EditorUndoHistory(byteLimit: 1)
    var value = 1
    history.record(
      scope: UUID(),
      estimatedByteCost: 2,
      undo: {
        value = 0
        return true
      },
      redo: {
        value = 1
        return true
      })

    #expect(history.canUndo)
    #expect(await history.undo())
    #expect(value == 0)
  }

}

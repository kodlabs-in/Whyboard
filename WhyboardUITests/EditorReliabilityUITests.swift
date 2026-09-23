@preconcurrency import XCTest

final class EditorReliabilityUITests: XCTestCase {
  nonisolated(unsafe) private var app: XCUIApplication?

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = MainActor.assumeIsolated {
      XCUIDevice.shared.orientation = .landscapeLeft
      let application = XCUIApplication()
      application.launchArguments = ["-ui-testing"]
      application.launch()
      return application
    }
  }

  @MainActor
  func testUndoAndRedoRestoreADeletedWorkspaceObject() throws {
    let app = try XCTUnwrap(app)
    app.buttons["New Note"].firstMatch.tap()
    selectNoteType("new-note-type-infiniteCanvas", in: app)
    XCTAssertTrue(app.navigationBars["Untitled Note"].waitForExistence(timeout: 5))

    app.buttons["Insert"].tap()
    app.buttons["Shape"].tap()
    app.buttons["Circle"].tap()
    let circle = app.descendants(matching: .any)["Circle"].firstMatch
    XCTAssertTrue(circle.waitForExistence(timeout: 3))

    app.buttons["workspace-delete-object"].tap()
    XCTAssertFalse(circle.waitForExistence(timeout: 1))

    let undo = app.navigationBars["Untitled Note"].buttons["Undo"]
    XCTAssertTrue(undo.isEnabled)
    undo.tap()
    XCTAssertTrue(circle.waitForExistence(timeout: 3))

    let redo = app.navigationBars["Untitled Note"].buttons["Redo"]
    XCTAssertTrue(redo.isEnabled)
    redo.tap()
    XCTAssertFalse(circle.waitForExistence(timeout: 1))
  }

  @MainActor
  private func selectNoteType(_ identifier: String, in app: XCUIApplication) {
    let noteType = app.buttons[identifier]
    XCTAssertTrue(noteType.waitForExistence(timeout: 3))
    noteType.tap()
  }
}

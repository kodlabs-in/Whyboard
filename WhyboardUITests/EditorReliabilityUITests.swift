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

    app.buttons["Object Actions"].tap()
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
  func testTextSizeAndColorControlsOnInfiniteCanvas() throws {
    let app = try XCTUnwrap(app)
    app.buttons["New Note"].firstMatch.tap()
    selectNoteType("new-note-type-infiniteCanvas", in: app)
    XCTAssertTrue(app.navigationBars["Untitled Note"].waitForExistence(timeout: 5))

    app.buttons["Insert"].tap()
    app.buttons["Text"].tap()
    XCTAssertTrue(app.navigationBars["Edit Text"].waitForExistence(timeout: 3))
    let editor = app.textViews.firstMatch
    XCTAssertTrue(editor.waitForExistence(timeout: 3))
    editor.tap()
    editor.typeText("Large title")

    let size = app.textFields["text-font-size"]
    XCTAssertTrue(size.exists)
    XCTAssertTrue(app.descendants(matching: .any)["text-color-picker"].firstMatch.exists)
    size.tap()
    size.typeKey("a", modifierFlags: .command)
    size.typeText("42")
    app.buttons["Save"].tap()

    let textObject = app.descendants(matching: .any)["Text, Large title"].firstMatch
    XCTAssertTrue(textObject.waitForExistence(timeout: 3))
    textObject.doubleTap()
    XCTAssertTrue(app.navigationBars["Edit Text"].waitForExistence(timeout: 3))
    XCTAssertEqual(app.textFields["text-font-size"].value as? String, "42")
  }

  @MainActor
  func testWritingEnablesUndoAndRedo() throws {
    try XCTUnwrap(app).terminate()
    let drawingApp = XCUIApplication()
    drawingApp.launchArguments = ["-ui-testing"]
    drawingApp.launchEnvironment["WHYBOARD_UI_TEST_DRAW_WITH_FINGER"] = "1"
    drawingApp.launch()

    drawingApp.buttons["New Note"].firstMatch.tap()
    selectNoteType("new-note-type-infiniteCanvas", in: drawingApp)
    XCTAssertTrue(drawingApp.navigationBars["Untitled Note"].waitForExistence(timeout: 5))
    let canvas = drawingApp.descendants(matching: .any)["infinite-canvas"].firstMatch
    XCTAssertTrue(canvas.waitForExistence(timeout: 5))
    XCTAssertEqual(canvas.value as? String, "0 strokes")
    let undo = drawingApp.navigationBars["Untitled Note"].buttons["Undo"]
    XCTAssertFalse(undo.isEnabled)

    for stroke in 1...3 {
      let horizontalPosition = 0.35 + Double(stroke) * 0.1
      let start = canvas.coordinate(
        withNormalizedOffset: CGVector(dx: horizontalPosition, dy: 0.45))
      let end = canvas.coordinate(
        withNormalizedOffset: CGVector(dx: horizontalPosition, dy: 0.55))
      start.press(forDuration: 0.05, thenDragTo: end)
      let strokeLabel = stroke == 1 ? "1 stroke" : "\(stroke) strokes"
      XCTAssertEqual(canvas.value as? String, strokeLabel)
    }
    let undoEnabled = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "enabled == true"),
      object: undo)
    XCTAssertEqual(
      XCTWaiter.wait(for: [undoEnabled], timeout: 3), .completed,
      "A completed drawing gesture should enable Undo")
    let redo = drawingApp.navigationBars["Untitled Note"].buttons["Redo"]
    for remaining in (0...2).reversed() {
      undo.tap()
      let strokeLabel = remaining == 1 ? "1 stroke" : "\(remaining) strokes"
      XCTAssertEqual(canvas.value as? String, strokeLabel)
    }
    XCTAssertFalse(undo.isEnabled)

    for restored in 1...3 {
      XCTAssertTrue(redo.isEnabled)
      redo.tap()
      let strokeLabel = restored == 1 ? "1 stroke" : "\(restored) strokes"
      XCTAssertEqual(canvas.value as? String, strokeLabel)
    }
  }

  @MainActor
  func testWritingOnAPageEnablesUndo() throws {
    try XCTUnwrap(app).terminate()
    let drawingApp = XCUIApplication()
    drawingApp.launchArguments = ["-ui-testing"]
    drawingApp.launchEnvironment["WHYBOARD_UI_TEST_DRAW_WITH_FINGER"] = "1"
    drawingApp.launch()

    drawingApp.buttons["New Note"].firstMatch.tap()
    selectNoteType("new-note-type-infinitePages", in: drawingApp)
    XCTAssertTrue(drawingApp.navigationBars["Untitled Note"].waitForExistence(timeout: 5))
    let canvas = drawingApp.descendants(matching: .any)["page-canvas"].firstMatch
    XCTAssertTrue(canvas.waitForExistence(timeout: 5))
    let undo = drawingApp.navigationBars["Untitled Note"].buttons["Undo"]
    XCTAssertFalse(undo.isEnabled)

    let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.45))
    let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.55))
    start.press(forDuration: 0.05, thenDragTo: end)

    let undoEnabled = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "enabled == true"),
      object: undo)
    XCTAssertEqual(
      XCTWaiter.wait(for: [undoEnabled], timeout: 3), .completed,
      "A completed page drawing gesture should enable Undo")
    undo.tap()
    XCTAssertEqual(canvas.value as? String, "0 strokes")
  }

  @MainActor
  func testErasingInkCanBeUndone() throws {
    try XCTUnwrap(app).terminate()
    let drawingApp = XCUIApplication()
    drawingApp.launchArguments = ["-ui-testing"]
    drawingApp.launchEnvironment["WHYBOARD_UI_TEST_DRAW_WITH_FINGER"] = "1"
    drawingApp.launch()

    drawingApp.buttons["New Note"].firstMatch.tap()
    selectNoteType("new-note-type-infiniteCanvas", in: drawingApp)
    XCTAssertTrue(drawingApp.navigationBars["Untitled Note"].waitForExistence(timeout: 5))
    let canvas = drawingApp.descendants(matching: .any)["infinite-canvas"].firstMatch
    XCTAssertTrue(canvas.waitForExistence(timeout: 5))
    let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
    let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5))
    start.press(forDuration: 0.05, thenDragTo: end)
    XCTAssertEqual(canvas.value as? String, "1 stroke")

    drawingApp.buttons["Pen"].firstMatch.tap()
    let eraser = drawingApp.buttons.matching(
      NSPredicate(format: "label CONTAINS[c] %@", "eraser")
    ).firstMatch
    XCTAssertTrue(eraser.waitForExistence(timeout: 3), drawingApp.debugDescription)
    eraser.tap()
    let eraseStart = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
    let eraseEnd = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5))
    eraseStart.press(forDuration: 0.05, thenDragTo: eraseEnd)
    XCTAssertEqual(canvas.value as? String, "0 strokes")
    let undo = drawingApp.navigationBars["Untitled Note"].buttons["Undo"]
    XCTAssertTrue(undo.isEnabled)
    undo.tap()
    let restoredStroke = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", "1 stroke"),
      object: canvas)
    XCTAssertEqual(XCTWaiter.wait(for: [restoredStroke], timeout: 3), .completed)
  }

  @MainActor
  private func selectNoteType(_ identifier: String, in app: XCUIApplication) {
    let noteType = app.buttons[identifier]
    XCTAssertTrue(noteType.waitForExistence(timeout: 3))
    noteType.tap()
  }
}

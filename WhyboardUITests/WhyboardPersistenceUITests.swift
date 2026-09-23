@preconcurrency import XCTest

final class WhyboardPersistenceUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testNoteAndShapeSurviveProcessRelaunch() {
    XCUIDevice.shared.orientation = .landscapeLeft
    let storageID = "note-and-shape-process-relaunch"
    var app = launchPersistentApp(storageID: storageID, resetsStorage: true)

    XCTAssertTrue(app.navigationBars["Whyboard"].waitForExistence(timeout: 5))
    app.buttons["New Note"].firstMatch.tap()
    selectNoteType("new-note-type-infiniteCanvas", in: app)
    XCTAssertTrue(app.navigationBars["Untitled Note"].waitForExistence(timeout: 5))

    app.buttons["Insert"].tap()
    app.buttons["Shape"].tap()
    app.buttons["Circle"].tap()
    XCTAssertTrue(workspaceObject("Circle", in: app).waitForExistence(timeout: 3))
    let returnToDrawing = app.buttons["Return to Drawing"]
    XCTAssertTrue(returnToDrawing.waitForExistence(timeout: 3))
    returnToDrawing.tap()
    XCTAssertTrue(app.buttons["Arrange Objects"].waitForExistence(timeout: 3))

    let canvas = app.descendants(matching: .any)["infinite-canvas"].firstMatch
    XCTAssertTrue(canvas.waitForExistence(timeout: 3))
    canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.35))
      .press(
        forDuration: 0.1,
        thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.6)))
    let strokeSaved = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", "1 stroke"),
      object: canvas)
    XCTAssertEqual(XCTWaiter.wait(for: [strokeSaved], timeout: 5), .completed)

    app.navigationBars["Untitled Note"].buttons.element(boundBy: 0).tap()
    XCTAssertTrue(app.staticTexts["Untitled Note"].firstMatch.waitForExistence(timeout: 5))
    app.terminate()

    app = launchPersistentApp(storageID: storageID, resetsStorage: false)
    let note = app.staticTexts["Untitled Note"].firstMatch
    XCTAssertTrue(note.waitForExistence(timeout: 5))
    note.tap()
    XCTAssertTrue(app.navigationBars["Untitled Note"].waitForExistence(timeout: 5))
    let reopenedCanvas = app.descendants(matching: .any)["infinite-canvas"].firstMatch
    XCTAssertTrue(reopenedCanvas.waitForExistence(timeout: 5))
    XCTAssertEqual(reopenedCanvas.value as? String, "1 stroke")
    app.buttons["Arrange Objects"].tap()
    XCTAssertTrue(workspaceObject("Circle", in: app).waitForExistence(timeout: 5))
  }

  @MainActor
  private func launchPersistentApp(storageID: String, resetsStorage: Bool) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing", "-ui-testing-persistent"]
    if resetsStorage {
      app.launchArguments.append("-ui-testing-reset")
    }
    app.launchEnvironment["WHYBOARD_UI_TEST_ID"] = storageID
    app.launchEnvironment["WHYBOARD_UI_TEST_DRAW_WITH_FINGER"] = "1"
    app.launch()
    return app
  }

  @MainActor
  private func selectNoteType(_ identifier: String, in app: XCUIApplication) {
    let noteType = app.buttons[identifier]
    XCTAssertTrue(noteType.waitForExistence(timeout: 3))
    noteType.tap()
  }

  @MainActor
  private func workspaceObject(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)[identifier].firstMatch
  }
}

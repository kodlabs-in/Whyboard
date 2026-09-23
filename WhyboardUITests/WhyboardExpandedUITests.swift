@preconcurrency import XCTest

final class WhyboardExpandedUITests: XCTestCase {
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
  func testDeletesASecondPageAndKeepsTheRequiredFirstPage() throws {
    let app = try XCTUnwrap(app)
    app.buttons["New Note"].firstMatch.tap()
    selectNoteType("new-note-type-infinitePages", in: app)
    XCTAssertTrue(app.navigationBars["Untitled Note"].waitForExistence(timeout: 5))

    app.buttons["Add Page"].firstMatch.tap()
    let secondPage = app.descendants(matching: .any)["Page 2"].firstMatch
    XCTAssertTrue(secondPage.waitForExistence(timeout: 5))
    let pageActions = app.buttons["Page 2 actions"]
    XCTAssertTrue(pageActions.waitForExistence(timeout: 3))
    pageActions.tap()
    app.buttons["Delete Page"].tap()

    let deletionAlert = app.alerts["Delete page?"]
    XCTAssertTrue(deletionAlert.waitForExistence(timeout: 3))
    deletionAlert.buttons["Delete Page"].tap()

    XCTAssertFalse(secondPage.waitForExistence(timeout: 1))
    XCTAssertTrue(
      app.descendants(matching: .any)["Page 1"].firstMatch.waitForExistence(timeout: 3))
    app.buttons["Arrange Pages"].tap()
    XCTAssertTrue(app.buttons["page-organizer-page-1"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["page-organizer-page-2"].exists)
    attachScreenshot(named: "Single required page after deletion")
  }

  @MainActor
  func testRenamesSearchesAndReopensANote() throws {
    let app = try XCTUnwrap(app)
    app.buttons["New Note"].firstMatch.tap()
    selectNoteType("new-note-type-infinitePages", in: app)
    XCTAssertTrue(app.navigationBars["Untitled Note"].waitForExistence(timeout: 5))

    app.buttons["Note Options"].tap()
    app.buttons["Rename Note"].tap()
    XCTAssertTrue(app.navigationBars["Rename Note"].waitForExistence(timeout: 3))
    let nameField = app.textFields["Name"]
    XCTAssertTrue(nameField.waitForExistence(timeout: 3))
    nameField.tap()
    nameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
    nameField.typeText("Trigonometry")
    app.buttons["Save"].tap()

    XCTAssertTrue(app.navigationBars["Trigonometry"].waitForExistence(timeout: 3))
    app.navigationBars["Trigonometry"].buttons.element(boundBy: 0).tap()
    XCTAssertTrue(app.staticTexts["Trigonometry"].firstMatch.waitForExistence(timeout: 5))

    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 3))
    search.tap()
    search.typeText("TRIG")
    XCTAssertTrue(app.staticTexts["Trigonometry"].firstMatch.waitForExistence(timeout: 3))
    app.staticTexts["Trigonometry"].firstMatch.tap()

    XCTAssertTrue(app.navigationBars["Trigonometry"].waitForExistence(timeout: 5))
    attachScreenshot(named: "Renamed note reopened from search")
  }

  @MainActor
  func testEditsExistingTextAndKeepsItAfterReopening() throws {
    let app = try XCTUnwrap(app)
    app.buttons["New Note"].firstMatch.tap()
    selectNoteType("new-note-type-infinitePages", in: app)
    XCTAssertTrue(app.navigationBars["Untitled Note"].waitForExistence(timeout: 5))

    app.buttons["Insert"].tap()
    app.buttons["Text"].tap()
    let editor = app.textViews.firstMatch
    XCTAssertTrue(editor.waitForExistence(timeout: 3))
    editor.tap()
    editor.typeText("Draft theorem")
    app.buttons["Save"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["Text, Draft theorem"].waitForExistence(timeout: 3))

    app.navigationBars["Untitled Note"].buttons.element(boundBy: 0).tap()
    app.staticTexts["Untitled Note"].firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Untitled Note"].waitForExistence(timeout: 5))
    app.buttons["Arrange Objects"].tap()
    let existingText = app.descendants(matching: .any)["Text, Draft theorem"].firstMatch
    XCTAssertTrue(existingText.waitForExistence(timeout: 3))
    existingText.doubleTap()

    XCTAssertTrue(editor.waitForExistence(timeout: 3))
    editor.tap()
    editor.typeKey("a", modifierFlags: .command)
    editor.typeText("Proved theorem")
    app.buttons["Save"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["Text, Proved theorem"].waitForExistence(timeout: 3))

    app.navigationBars["Untitled Note"].buttons.element(boundBy: 0).tap()
    app.staticTexts["Untitled Note"].firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Untitled Note"].waitForExistence(timeout: 5))
    app.buttons["Arrange Objects"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["Text, Proved theorem"].waitForExistence(timeout: 3))
    attachScreenshot(named: "Edited text after reopening")
  }

  @MainActor
  func testDeletesOnlyTheSelectedShapeFromAnOverlappingDiagram() throws {
    let app = try XCTUnwrap(app)
    app.buttons["New Note"].firstMatch.tap()
    selectNoteType("new-note-type-infiniteCanvas", in: app)
    XCTAssertTrue(app.navigationBars["Untitled Note"].waitForExistence(timeout: 5))

    app.buttons["Insert"].tap()
    app.buttons["Shape"].tap()
    app.buttons["Circle"].tap()
    let circle = app.descendants(matching: .any)["Circle"].firstMatch
    XCTAssertTrue(circle.waitForExistence(timeout: 3))

    app.buttons["Insert"].tap()
    app.buttons["Shape"].tap()
    app.buttons["Line"].tap()
    let line = app.descendants(matching: .any)["Line"].firstMatch
    XCTAssertTrue(line.waitForExistence(timeout: 3))
    XCTAssertTrue(circle.frame.intersects(line.frame))

    app.buttons["Object Actions"].tap()
    let delete = app.buttons["workspace-delete-object"]
    XCTAssertTrue(delete.waitForExistence(timeout: 3))
    delete.tap()

    XCTAssertFalse(line.waitForExistence(timeout: 1))
    XCTAssertTrue(circle.exists)

    app.navigationBars["Untitled Note"].buttons.element(boundBy: 0).tap()
    XCTAssertTrue(app.staticTexts["Untitled Note"].firstMatch.waitForExistence(timeout: 5))
    app.staticTexts["Untitled Note"].firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Untitled Note"].waitForExistence(timeout: 5))
    app.buttons["Arrange Objects"].tap()

    XCTAssertTrue(app.descendants(matching: .any)["Circle"].firstMatch.waitForExistence(timeout: 3))
    XCTAssertFalse(app.descendants(matching: .any)["Line"].firstMatch.exists)
    attachScreenshot(named: "Overlapping diagram after reopening")
  }

  @MainActor
  func testBulkDeletesTwoSelectedNotes() throws {
    let app = try XCTUnwrap(app)
    app.buttons["New Note"].firstMatch.tap()
    selectNoteType("new-note-type-infinitePages", in: app)
    XCTAssertTrue(app.navigationBars["Untitled Note"].waitForExistence(timeout: 5))
    app.navigationBars["Untitled Note"].buttons.element(boundBy: 0).tap()

    let originalTitle = app.staticTexts["Untitled Note"].firstMatch
    XCTAssertTrue(originalTitle.waitForExistence(timeout: 5))
    originalTitle.press(forDuration: 1)
    app.buttons["Duplicate"].tap()
    XCTAssertTrue(app.staticTexts["Untitled Note Copy"].waitForExistence(timeout: 5))

    app.buttons["library-select-mode"].tap()
    app.buttons["Select All"].tap()
    XCTAssertTrue(app.staticTexts["2 selected"].waitForExistence(timeout: 3))
    app.buttons["Delete"].tap()

    let deletionAlert = app.alerts["Delete 2 Selected Items?"]
    XCTAssertTrue(deletionAlert.waitForExistence(timeout: 3))
    deletionAlert.buttons["Delete All"].tap()

    XCTAssertTrue(app.staticTexts["This folder is ready"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Untitled Note"].exists)
    XCTAssertFalse(app.staticTexts["Untitled Note Copy"].exists)
    attachScreenshot(named: "Empty library after bulk deletion")
  }

  @MainActor
  func testLibraryAndEditorSmokeInPortrait() throws {
    let originalApp = try XCTUnwrap(app)
    originalApp.terminate()
    XCUIDevice.shared.orientation = .portrait
    let portraitApp = XCUIApplication()
    portraitApp.launchArguments = ["-ui-testing"]
    portraitApp.launch()

    XCTAssertTrue(portraitApp.navigationBars["Whyboard"].waitForExistence(timeout: 5))
    XCTAssertTrue(portraitApp.buttons["New Note"].firstMatch.isHittable)
    portraitApp.buttons["New Note"].firstMatch.tap()
    selectNoteType("new-note-type-infiniteCanvas", in: portraitApp)
    XCTAssertTrue(portraitApp.navigationBars["Untitled Note"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      portraitApp.descendants(matching: .any)["infinite-canvas"].firstMatch
        .waitForExistence(timeout: 3))
    attachScreenshot(named: "Portrait editor smoke")
  }

  @MainActor
  func testLibrarySmokeInDarkModeWithAccessibilityText() throws {
    let originalApp = try XCTUnwrap(app)
    originalApp.terminate()
    let adaptiveApp = XCUIApplication()
    adaptiveApp.launchArguments = [
      "-ui-testing",
      "-AppleInterfaceStyle", "Dark",
      "-UIPreferredContentSizeCategoryName",
      "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
    ]
    adaptiveApp.launch()

    XCTAssertTrue(adaptiveApp.navigationBars["Whyboard"].waitForExistence(timeout: 5))
    let newNote = adaptiveApp.buttons["New Note"].firstMatch
    XCTAssertTrue(newNote.waitForExistence(timeout: 3))
    XCTAssertTrue(newNote.isHittable)
    newNote.tap()
    XCTAssertTrue(adaptiveApp.buttons["new-note-type-infinitePages"].waitForExistence(timeout: 3))
    attachScreenshot(named: "Dark mode accessibility text smoke")
  }

  @MainActor
  private func attachScreenshot(named name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  private func selectNoteType(_ identifier: String, in app: XCUIApplication) {
    let noteType = app.buttons[identifier]
    XCTAssertTrue(noteType.waitForExistence(timeout: 3))
    noteType.tap()
  }
}

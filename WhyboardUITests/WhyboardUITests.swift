@preconcurrency import XCTest

final class WhyboardUITests: XCTestCase {
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
  func testCreatesANoteAndAddsASecondPage() throws {
    let app = try XCTUnwrap(app)
    XCTAssertTrue(app.navigationBars["Whyboard"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["All Notes"].exists)
    XCTAssertFalse(app.staticTexts["Unfiled Notes"].exists)

    let newNoteButton = app.buttons["New Note"].firstMatch
    XCTAssertTrue(newNoteButton.waitForExistence(timeout: 3))
    newNoteButton.tap()
    selectNoteType("new-note-type-infinitePages", in: app)

    XCTAssertTrue(app.navigationBars["Untitled Note"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.otherElements["Page 1"].waitForExistence(timeout: 5))

    let addPageButton = app.buttons["Add Page"].firstMatch
    XCTAssertTrue(addPageButton.waitForExistence(timeout: 3))
    addPageButton.tap()

    XCTAssertTrue(app.otherElements["Page 2"].waitForExistence(timeout: 5))

    app.buttons["Arrange Pages"].tap()
    XCTAssertTrue(app.buttons["page-organizer-page-1"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["page-organizer-page-2"].waitForExistence(timeout: 3))
    attachScreenshot(named: "Page organiser thumbnails")
    app.buttons["Done"].tap()

    app.buttons["jump-to-page"].tap()
    let jumpField = app.textFields["jump-to-page-field"]
    XCTAssertTrue(jumpField.waitForExistence(timeout: 3))
    attachScreenshot(named: "Jump to page")
    jumpField.tap()
    jumpField.typeText(XCUIKeyboardKey.delete.rawValue)
    jumpField.typeText("2")
    app.buttons["jump-to-page-go"].tap()
    XCTAssertTrue(app.otherElements["Page 2"].waitForExistence(timeout: 3))
    attachScreenshot(named: "Editor with two pages")
  }

  @MainActor
  func testDuplicatesAPageAndItsNote() throws {
    let app = try XCTUnwrap(app)
    app.buttons["New Note"].firstMatch.tap()
    selectNoteType("new-note-type-infinitePages", in: app)
    XCTAssertTrue(app.navigationBars["Untitled Note"].waitForExistence(timeout: 5))

    let pageActions = app.buttons["Page 1 actions"]
    XCTAssertTrue(pageActions.waitForExistence(timeout: 3))
    pageActions.tap()
    let duplicatePage = app.buttons["Duplicate Page"]
    XCTAssertTrue(duplicatePage.waitForExistence(timeout: 3))
    duplicatePage.tap()
    XCTAssertTrue(app.otherElements["Page 2"].waitForExistence(timeout: 5))

    app.navigationBars["Untitled Note"].buttons.element(boundBy: 0).tap()
    let originalTitle = app.staticTexts["Untitled Note"].firstMatch
    XCTAssertTrue(originalTitle.waitForExistence(timeout: 5))
    originalTitle.press(forDuration: 1)
    let duplicateNote = app.buttons["Duplicate"]
    XCTAssertTrue(duplicateNote.waitForExistence(timeout: 3))
    duplicateNote.tap()

    let copyTitle = app.staticTexts["Untitled Note Copy"]
    XCTAssertTrue(copyTitle.waitForExistence(timeout: 5))
    copyTitle.tap()
    XCTAssertTrue(app.navigationBars["Untitled Note Copy"].waitForExistence(timeout: 5))
    app.buttons["Arrange Pages"].tap()
    XCTAssertTrue(app.buttons["page-organizer-page-1"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["page-organizer-page-2"].waitForExistence(timeout: 3))
    attachScreenshot(named: "Duplicated note pages")
  }

  @MainActor
  func testFavoritesAndRecentsAppearOnLibraryHome() throws {
    let app = try XCTUnwrap(app)
    app.buttons["New Note"].firstMatch.tap()
    selectNoteType("new-note-type-infinitePages", in: app)
    XCTAssertTrue(app.navigationBars["Untitled Note"].waitForExistence(timeout: 5))
    app.navigationBars["Untitled Note"].buttons.element(boundBy: 0).tap()

    XCTAssertTrue(app.staticTexts["Recent"].waitForExistence(timeout: 5))
    let favoriteButton = app.buttons["Add to Favorites"].firstMatch
    XCTAssertTrue(favoriteButton.waitForExistence(timeout: 3))
    favoriteButton.tap()
    XCTAssertTrue(app.staticTexts["Favorites"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["Remove from Favorites"].firstMatch.exists)
    attachScreenshot(named: "Favorites and recent notes")
  }

  @MainActor
  func testCreatesAndZoomsAnInfiniteCanvas() throws {
    let app = try XCTUnwrap(app)
    let newNoteButton = app.buttons["New Note"].firstMatch
    XCTAssertTrue(newNoteButton.waitForExistence(timeout: 5))
    newNoteButton.tap()
    selectNoteType("new-note-type-infiniteCanvas", in: app)

    XCTAssertTrue(app.navigationBars["Untitled Note"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      app.descendants(matching: .any)["infinite-canvas"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Pinch to zoom • Drag with two fingers to move"].exists)

    let zoomInButton = app.buttons["canvas-zoom-in"]
    XCTAssertTrue(zoomInButton.waitForExistence(timeout: 3))
    zoomInButton.tap()

    let zoomPercentage = app.descendants(matching: .any)["canvas-zoom-percentage"]
    XCTAssertTrue(zoomPercentage.waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["125%"].waitForExistence(timeout: 3))

    app.buttons["Insert"].tap()
    app.buttons["Shape"].tap()
    app.buttons["Rectangle"].tap()
    XCTAssertTrue(app.otherElements["Rectangle"].waitForExistence(timeout: 3))

    let shape = app.otherElements["Rectangle"].firstMatch
    let resizeHandle = app.otherElements["Resize object"].firstMatch
    XCTAssertTrue(shape.waitForExistence(timeout: 3))
    XCTAssertTrue(resizeHandle.waitForExistence(timeout: 3))
    let initialFrame = shape.frame
    let resizeStart = resizeHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    resizeStart.press(
      forDuration: 0.1,
      thenDragTo: resizeStart.withOffset(CGVector(dx: 90, dy: 60)))

    XCTAssertGreaterThan(shape.frame.width, initialFrame.width)
    XCTAssertGreaterThan(shape.frame.height, initialFrame.height)
    attachScreenshot(named: "Infinite canvas editor")
  }

  @MainActor
  func testAddsEditableTextToAnInfinitePagesNote() throws {
    let app = try XCTUnwrap(app)
    app.buttons["New Note"].firstMatch.tap()
    selectNoteType("new-note-type-infinitePages", in: app)
    XCTAssertTrue(app.navigationBars["Untitled Note"].waitForExistence(timeout: 5))

    app.buttons["Insert"].tap()
    app.buttons["Text"].tap()
    XCTAssertTrue(app.navigationBars["Edit Text"].waitForExistence(timeout: 3))
    let editor = app.textViews.firstMatch
    XCTAssertTrue(editor.waitForExistence(timeout: 3))
    editor.tap()
    editor.typeText("A visual idea")
    app.buttons["Save"].tap()

    let textObject = app.otherElements["Text, A visual idea"]
    XCTAssertTrue(textObject.waitForExistence(timeout: 3))
    attachScreenshot(named: "Text object on page")
  }

  @MainActor
  func testCreatesAndSelectsAFolder() throws {
    let app = try XCTUnwrap(app)
    let newFolderButton = app.buttons["New Folder"].firstMatch
    XCTAssertTrue(newFolderButton.waitForExistence(timeout: 5))
    newFolderButton.tap()

    XCTAssertTrue(app.navigationBars["New Folder"].waitForExistence(timeout: 3))
    let nameField = app.textFields["Name"]
    XCTAssertTrue(nameField.waitForExistence(timeout: 3))
    nameField.tap()
    nameField.typeText("Calculus")
    app.buttons["Save"].tap()

    let folder = app.staticTexts["Calculus"]
    XCTAssertTrue(folder.waitForExistence(timeout: 5))
    folder.tap()
    XCTAssertTrue(app.navigationBars["Calculus"].waitForExistence(timeout: 3))
    attachScreenshot(named: "Library folder")
  }

  @MainActor
  func testChangesTheDefaultPaperInSettings() throws {
    let app = try XCTUnwrap(app)
    let settingsButton = app.buttons["Settings"]
    XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
    settingsButton.tap()

    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    let defaultPaper = app.descendants(matching: .any)["default-paper-picker"]
    XCTAssertTrue(defaultPaper.waitForExistence(timeout: 3))
    defaultPaper.tap()
    app.buttons["Black"].tap()
    XCTAssertTrue(app.staticTexts["Black"].waitForExistence(timeout: 3))
    attachScreenshot(named: "Settings paper selection")
  }

  @MainActor
  func testSelectModeSelectsAndClearsANote() throws {
    let app = try XCTUnwrap(app)
    app.buttons["New Note"].firstMatch.tap()
    selectNoteType("new-note-type-infinitePages", in: app)
    XCTAssertTrue(app.navigationBars["Untitled Note"].waitForExistence(timeout: 5))
    app.navigationBars["Untitled Note"].buttons.element(boundBy: 0).tap()

    let selectMode = app.buttons["library-select-mode"]
    XCTAssertTrue(selectMode.waitForExistence(timeout: 3))
    selectMode.tap()
    XCTAssertTrue(app.buttons["Select All"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["Extend Selection Backward"].exists)
    XCTAssertFalse(app.buttons["Extend Selection Forward"].exists)
    app.staticTexts["Untitled Note"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["1 selected"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["Move"].exists)
    XCTAssertTrue(app.buttons["Delete"].exists)
    attachScreenshot(named: "Library select mode")

    app.buttons["Cancel"].tap()
    XCTAssertFalse(app.staticTexts["1 selected"].exists)
  }

  @MainActor
  func testDocumentAndBackupActionsAreAccessible() throws {
    let app = try XCTUnwrap(app)
    XCTAssertTrue(app.buttons["Import PDF"].waitForExistence(timeout: 5))

    app.buttons["New Note"].firstMatch.tap()
    selectNoteType("new-note-type-infinitePages", in: app)
    XCTAssertTrue(app.navigationBars["Untitled Note"].waitForExistence(timeout: 5))
    app.navigationBars["Untitled Note"].buttons.element(boundBy: 0).tap()
    app.staticTexts["Untitled Note"].firstMatch.press(forDuration: 1)
    XCTAssertTrue(app.buttons["Export PDF"].waitForExistence(timeout: 3))
    app.tap()

    app.buttons["Settings"].tap()
    XCTAssertTrue(app.buttons["create-backup"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["⌘P"].exists)
    app.swipeUp()
    XCTAssertTrue(app.buttons["restore-backup"].waitForExistence(timeout: 3))
    attachScreenshot(named: "Document and backup actions")
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

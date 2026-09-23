@preconcurrency import XCTest

final class LibrarySearchUITests: XCTestCase {
  @MainActor
  func testSearchHidesUnrelatedSmartSectionsAndNotes() throws {
    XCUIDevice.shared.orientation = .landscapeLeft
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing"]
    app.launch()

    createAndRenameNote("Calculus", in: app)
    let favorite = app.buttons["Add to Favorites"].firstMatch
    XCTAssertTrue(favorite.waitForExistence(timeout: 3))
    XCTAssertGreaterThanOrEqual(favorite.frame.width, 44)
    XCTAssertGreaterThanOrEqual(favorite.frame.height, 44)
    favorite.tap()
    createAndRenameNote("Physics", in: app)

    XCTAssertTrue(app.staticTexts["Favorites"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["Recent"].exists)
    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 3))
    search.tap()
    search.typeText("Calculus")

    XCTAssertTrue(app.staticTexts["Calculus"].firstMatch.waitForExistence(timeout: 3))
    XCTAssertFalse(app.staticTexts["Physics"].exists)
    XCTAssertFalse(app.staticTexts["Favorites"].exists)
    XCTAssertFalse(app.staticTexts["Recent"].exists)
  }

  @MainActor
  private func createAndRenameNote(_ title: String, in app: XCUIApplication) {
    app.buttons["New Note"].firstMatch.tap()
    let noteType = app.buttons["new-note-type-infinitePages"]
    XCTAssertTrue(noteType.waitForExistence(timeout: 3))
    noteType.tap()
    XCTAssertTrue(app.navigationBars["Untitled Note"].waitForExistence(timeout: 5))
    app.buttons["Note Options"].tap()
    let rename = app.buttons["Rename Note"]
    XCTAssertTrue(rename.waitForExistence(timeout: 5))
    rename.tap()
    XCTAssertTrue(app.navigationBars["Rename Note"].waitForExistence(timeout: 8))
    let field = app.textFields["Name"]
    XCTAssertTrue(field.waitForExistence(timeout: 8))
    field.tap()
    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
    field.typeText(title)
    app.buttons["Save"].tap()
    XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 3))
    app.navigationBars[title].buttons.element(boundBy: 0).tap()
    XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 5))
  }
}

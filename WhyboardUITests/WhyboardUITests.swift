import XCTest

final class WhyboardUITests: XCTestCase {
  private var app: XCUIApplication?

  override func setUpWithError() throws {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .landscapeLeft
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing"]
    app.launch()
    self.app = app
  }

  @MainActor
  func testCreatesANoteAndAddsASecondPage() throws {
    let app = try XCTUnwrap(app)
    XCTAssertTrue(app.staticTexts["All Notes"].waitForExistence(timeout: 5))

    let newNoteButton = app.buttons["New Note"].firstMatch
    XCTAssertTrue(newNoteButton.waitForExistence(timeout: 3))
    newNoteButton.tap()

    XCTAssertTrue(app.navigationBars["Untitled Note"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.otherElements["Page 1"].waitForExistence(timeout: 5))

    let addPageButton = app.buttons["Add Page"].firstMatch
    XCTAssertTrue(addPageButton.waitForExistence(timeout: 3))
    addPageButton.tap()

    XCTAssertTrue(app.otherElements["Page 2"].waitForExistence(timeout: 5))
    attachScreenshot(named: "Editor with two pages")
  }

  @MainActor
  func testCreatesAndSelectsAFolder() throws {
    let app = try XCTUnwrap(app)
    let newFolderButton = app.buttons["New Folder"]
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
  private func attachScreenshot(named name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}

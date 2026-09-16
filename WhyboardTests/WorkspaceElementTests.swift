import CoreGraphics
import Foundation
import Testing

@testable import Whyboard

@MainActor
struct WorkspaceElementTests {
  @Test func elementMetadataRoundTripsWithoutMediaBytes() throws {
    let element = WorkspaceElement(
      kind: .shape,
      frame: WorkspaceElementFrame(
        center: CGPoint(x: 320, y: 480),
        size: CGSize(width: 240, height: 180),
        rotationDegrees: 22),
      zIndex: 3,
      shapeKind: .triangle,
      color: .orange)

    let data = try WorkspaceElementCoding.encode([element])
    let decoded = WorkspaceElementCoding.decode(data)

    #expect(decoded == [element])
  }

  @Test func elementSessionPersistsTransformsAndDuplication() throws {
    let note = Note(folderID: UUID())
    let page = Page(noteID: note.id, sortOrder: 0)
    var saveCount = 0
    let session = ElementSession(
      page: page,
      note: note,
      canvasSize: CanonicalPage.size,
      saveMetadata: { saveCount += 1 },
      onError: { _ in })
    let elementID = session.addShape(.rectangle, at: CGPoint(x: 300, y: 400))
    let frame = try #require(session.element(withID: elementID)?.frame)

    session.commitFrame(
      frame
        .translated(by: CGSize(width: 80, height: 40), scale: 1)
        .rotated(by: 30),
      for: elementID)
    session.duplicateSelected()

    #expect(session.elements.count == 2)
    #expect(session.elements.first?.frame.center == CGPoint(x: 380, y: 440))
    #expect(session.elements.first?.frame.rotationDegrees == 30)
    #expect(page.workspaceElementsData != nil)
    #expect(saveCount == 3)
  }

  @Test func photoResizePreservesItsAspectRatio() {
    let frame = WorkspaceElementFrame(
      center: CGPoint(x: 400, y: 500),
      size: CGSize(width: 400, height: 200))

    let resized = frame.resizedPreservingAspectRatio(
      by: CGSize(width: 120, height: 15),
      scale: 1)

    #expect(resized.width / resized.height == 2)
    #expect(resized.width > frame.width)
    #expect(resized.height > frame.height)
  }

  @Test func legacyUnsupportedMediaDoesNotHideSupportedObjects() throws {
    let supported = WorkspaceElement(
      kind: .shape,
      frame: WorkspaceElementFrame(
        center: CGPoint(x: 200, y: 200),
        size: CGSize(width: 160, height: 120)),
      zIndex: 0,
      shapeKind: .rectangle)
    let supportedData = try JSONEncoder().encode(supported)
    let supportedObject = try #require(
      JSONSerialization.jsonObject(with: supportedData) as? [String: Any])
    var unsupportedObject = supportedObject
    unsupportedObject["id"] = UUID().uuidString
    unsupportedObject["kind"] = "audio"
    unsupportedObject["zIndex"] = 1
    unsupportedObject["assetFilename"] = "legacy-audio.m4a"
    let data = try JSONSerialization.data(
      withJSONObject: [supportedObject, unsupportedObject])

    let decoded = WorkspaceElementCoding.decode(data)

    #expect(decoded == [supported])
  }

  @Test func attachmentRepositoryCopiesAndDeletesImportedFiles() async throws {
    let directories = try AppDirectories.make(isTesting: true)
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let repository = AttachmentRepository(directories: directories)
    let source = directories.recovery.appending(path: "sample.jpg")
    try Data("photo-data".utf8).write(to: source)
    let noteID = UUID()
    let pageID = UUID()

    let filename = try await repository.importFile(
      at: source,
      noteID: noteID,
      pageID: pageID)
    let storedURL = repository.fileURL(noteID: noteID, pageID: pageID, filename: filename)
    #expect(FileManager.default.fileExists(atPath: storedURL.path))

    await repository.delete(filename: filename, noteID: noteID, pageID: pageID)
    #expect(!FileManager.default.fileExists(atPath: storedURL.path))
  }
}

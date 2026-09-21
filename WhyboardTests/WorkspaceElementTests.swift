import CoreGraphics
import Foundation
import SwiftUI
import Testing
import UIKit

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
    var previewRevisions: [Int64] = []
    let session = ElementSession(
      page: page,
      note: note,
      canvasSize: CanonicalPage.size,
      saveMetadata: { saveCount += 1 },
      onError: { _ in },
      onPreviewInvalidated: { _, revision in previewRevisions.append(revision) })
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
    #expect(page.contentRevision == 3)
    #expect(previewRevisions == [1, 2, 3])
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

  @Test func circleStartsAndResizesWithEqualDimensions() throws {
    let note = Note(folderID: UUID())
    let page = Page(noteID: note.id, sortOrder: 0)
    let session = ElementSession(
      page: page,
      note: note,
      canvasSize: CanonicalPage.size,
      saveMetadata: {},
      onError: { _ in })

    let circleID = session.addShape(.circle, at: CGPoint(x: 320, y: 480))
    let circle = try #require(session.element(withID: circleID))
    let resized = circle.frame.resizedPreservingAspectRatio(
      by: CGSize(width: 90, height: 20),
      scale: 1)

    #expect(circle.frame.width == circle.frame.height)
    #expect(resized.width == resized.height)
    #expect(WorkspaceElementCoding.decode(page.workspaceElementsData).first?.shapeKind == .circle)
  }

  @Test func overlappingShapesPersistIndependently() {
    let note = Note(folderID: UUID())
    let page = Page(noteID: note.id, sortOrder: 0)
    let session = ElementSession(
      page: page,
      note: note,
      canvasSize: CanonicalPage.size,
      saveMetadata: {},
      onError: { _ in })
    let center = CGPoint(x: 320, y: 480)

    let circleID = session.addShape(.circle, at: center)
    let lineID = session.addShape(.line, at: center)
    let decoded = WorkspaceElementCoding.decode(page.workspaceElementsData)

    #expect(decoded.map(\.id) == [circleID, lineID])
    #expect(decoded.allSatisfy { $0.frame.center == center })
  }

  @Test func invalidTransformDoesNotPoisonLaterSaves() throws {
    let note = Note(folderID: UUID())
    let page = Page(noteID: note.id, sortOrder: 0)
    var errors: [String] = []
    var saveCount = 0
    let session = ElementSession(
      page: page,
      note: note,
      canvasSize: CanonicalPage.size,
      saveMetadata: { saveCount += 1 },
      onError: { errors.append($0) })
    let lineID = session.addShape(.line, at: CGPoint(x: 320, y: 480))
    let original = try #require(session.element(withID: lineID)?.frame)
    let originalData = page.workspaceElementsData
    var invalid = original
    invalid.rotationDegrees = .nan

    session.commitFrame(invalid, for: lineID)

    #expect(session.element(withID: lineID)?.frame == original)
    #expect(page.workspaceElementsData == originalData)
    #expect(page.contentRevision == 1)
    #expect(saveCount == 1)
    #expect(errors.count == 1)

    session.commitFrame(original.rotated(by: 90), for: lineID)

    #expect(session.element(withID: lineID)?.frame.rotationDegrees == 90)
    #expect(WorkspaceElementCoding.decode(page.workspaceElementsData).count == 1)
    #expect(page.contentRevision == 2)
    #expect(saveCount == 2)
  }

  @Test func metadataFailureRestoresInMemoryAndPersistedGeometry() throws {
    let note = Note(folderID: UUID())
    let page = Page(noteID: note.id, sortOrder: 0)
    var failsSave = false
    var errors: [String] = []
    let session = ElementSession(
      page: page,
      note: note,
      canvasSize: CanonicalPage.size,
      saveMetadata: {
        if failsSave { throw WorkspaceElementTestError.saveFailed }
      },
      onError: { errors.append($0) })
    let shapeID = session.addShape(.rectangle, at: CGPoint(x: 300, y: 400))
    let original = try #require(session.element(withID: shapeID)?.frame)
    let originalData = page.workspaceElementsData
    let preview = original.translated(by: CGSize(width: 40, height: 20), scale: 1)
    session.previewFrame(preview, for: shapeID)
    #expect(session.element(withID: shapeID)?.frame == preview)
    failsSave = true

    session.commitFrame(
      original.translated(by: CGSize(width: 80, height: 40), scale: 1),
      for: shapeID)

    #expect(session.element(withID: shapeID)?.frame == original)
    #expect(page.workspaceElementsData == originalData)
    #expect(page.contentRevision == 1)
    #expect(errors == [WorkspaceElementTestError.saveFailed.localizedDescription])
  }

  @Test func deletingOneOverlappingShapePreservesItsSibling() {
    let note = Note(folderID: UUID())
    let page = Page(noteID: note.id, sortOrder: 0)
    let session = ElementSession(
      page: page,
      note: note,
      canvasSize: CanonicalPage.size,
      saveMetadata: {},
      onError: { _ in })
    let center = CGPoint(x: 320, y: 480)
    let circleID = session.addShape(.circle, at: center)
    let lineID = session.addShape(.line, at: center)
    session.select(circleID)

    _ = session.deleteSelected()

    #expect(session.elements.map(\.id) == [lineID])
    #expect(WorkspaceElementCoding.decode(page.workspaceElementsData).map(\.id) == [lineID])
  }

  @Test func openShapeHitRegionFollowsTheVisibleStroke() {
    let rect = CGRect(x: 0, y: 0, width: 240, height: 180)
    let line = WorkspaceElementHitShape(elementKind: .shape, shapeKind: .line).path(in: rect)
    let circle = WorkspaceElementHitShape(elementKind: .shape, shapeKind: .circle).path(in: rect)

    #expect(line.contains(CGPoint(x: rect.midX, y: rect.midY)))
    #expect(!line.contains(CGPoint(x: 12, y: 12)))
    #expect(circle.contains(CGPoint(x: rect.midX, y: rect.midY)))
    #expect(!circle.contains(CGPoint(x: 12, y: 12)))
  }

  @Test func invalidInteractionScaleLeavesFrameUnchanged() {
    let frame = WorkspaceElementFrame(
      center: CGPoint(x: 400, y: 500),
      size: CGSize(width: 200, height: 160))

    #expect(frame.translated(by: CGSize(width: 20, height: 30), scale: 0) == frame)
    #expect(frame.resized(by: CGSize(width: 20, height: 30), scale: .nan) == frame)
  }

  @Test func manifestEncodingRejectsNonFiniteGeometry() {
    var frame = WorkspaceElementFrame(
      center: CGPoint(x: 400, y: 500),
      size: CGSize(width: 200, height: 160))
    frame.centerX = .infinity
    let element = WorkspaceElement(kind: .shape, frame: frame, zIndex: 0, shapeKind: .line)

    #expect(throws: WorkspaceElementCodingError.invalidGeometry(element.id)) {
      try WorkspaceElementCoding.encode([element])
    }
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
    let directories = try AppDirectories.makeForTesting()
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

  @Test func attachmentImagesAreDecodedAtADeviceSizedResolution() throws {
    let directories = try AppDirectories.makeForTesting()
    defer { try? FileManager.default.removeItem(at: directories.root) }
    let source = directories.recovery.appending(path: "large-image.png")
    let original = UIGraphicsImageRenderer(size: CGSize(width: 1_024, height: 768)).image {
      UIColor.systemIndigo.setFill()
      $0.fill(CGRect(x: 0, y: 0, width: 1_024, height: 768))
    }
    try #require(original.pngData()).write(to: source, options: .atomic)

    let decoded = try #require(
      AttachmentImageDecoder.image(at: source, maximumPixelDimension: 256))

    #expect(max(decoded.size.width, decoded.size.height) <= 256)
    #expect(abs(decoded.size.width / decoded.size.height - 4.0 / 3.0) < 0.001)
  }
}

private enum WorkspaceElementTestError: LocalizedError {
  case saveFailed

  var errorDescription: String? { "Test metadata save failed." }
}

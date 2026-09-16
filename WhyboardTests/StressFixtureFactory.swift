import PencilKit
import SwiftData
import UIKit

@testable import Whyboard

struct PopulatedNotebookFixture {
  let container: ModelContainer
  let context: ModelContext
  let directories: AppDirectories
  let repository: DrawingRepository
  let note: Note
  let pages: [Page]
}

private enum StressFixtureError: Error {
  case imageEncodingFailed
}

@MainActor
enum StressFixtureFactory {
  static func notebook(pageCount: Int) async throws -> PopulatedNotebookFixture {
    let directories = try AppDirectories.makeForTesting()
    let repository = DrawingRepository(directories: directories)
    let container = try modelContainer()
    let context = container.mainContext
    let note = Note(folderID: fixedUUID(90_000), title: "Stress \(pageCount)")
    let imageURL = try fixtureImage(in: directories)
    var pages: [Page] = []
    pages.reserveCapacity(pageCount)

    context.insert(note)
    for index in 0..<pageCount {
      let page = try await populatedPage(
        at: index,
        noteID: note.id,
        imageURL: imageURL,
        repository: repository)
      context.insert(page)
      pages.append(page)
    }
    try context.save()

    return PopulatedNotebookFixture(
      container: container,
      context: context,
      directories: directories,
      repository: repository,
      note: note,
      pages: pages)
  }

  static func library(noteCount: Int) -> ([Folder], [Note]) {
    let folders = (0..<20).map { index in
      Folder(id: fixedUUID(100_000 + index), name: "Folder \(index)", sortOrder: index)
    }
    let notes = (0..<noteCount).map { index in
      let note = Note(
        id: fixedUUID(200_000 + index),
        folderID: folders[index % folders.count].id,
        title: "Notebook \(index % 100)",
        createdAt: Date(timeIntervalSince1970: Double(index % 7)),
        updatedAt: Date(timeIntervalSince1970: Double(index % 11)))
      note.isFavorite = index.isMultiple(of: 10)
      note.lastOpenedAt =
        index.isMultiple(of: 3)
        ? Date(timeIntervalSince1970: Double(index))
        : nil
      return note
    }
    return (folders, notes)
  }

  private static func modelContainer() throws -> ModelContainer {
    let schema = Schema([Folder.self, Note.self, Page.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
  }

  private static func populatedPage(
    at index: Int,
    noteID: UUID,
    imageURL: URL,
    repository: DrawingRepository
  ) async throws -> Page {
    let page = Page(
      id: fixedUUID(index + 1),
      noteID: noteID,
      sortOrder: index,
      contentRevision: Int64(index + 1))
    let filename = try await repository.attachments.importFile(
      at: imageURL,
      noteID: noteID,
      pageID: page.id)
    page.workspaceElementsData = try WorkspaceElementCoding.encode(
      elements(for: index, imageFilename: filename))
    try await repository.save(drawing(for: index), pageID: page.id, noteID: noteID)
    return page
  }

  private static func elements(
    for index: Int,
    imageFilename: String
  ) -> [WorkspaceElement] {
    let baseID = 300_000 + index * 6
    return [
      WorkspaceElement(
        id: fixedUUID(baseID),
        kind: .text,
        frame: WorkspaceElementFrame(
          center: CGPoint(x: 220, y: 130),
          size: CGSize(width: 300, height: 90)),
        zIndex: 0,
        text: "Notebook \(index + 1): structured idea and supporting details"),
      WorkspaceElement(
        id: fixedUUID(baseID + 1),
        kind: .text,
        frame: WorkspaceElementFrame(
          center: CGPoint(x: 480, y: 285),
          size: CGSize(width: 250, height: 80)),
        zIndex: 1,
        text: "Review, connect, and refine this page"),
      shapeElement(
        id: baseID + 2, kind: .rectangle, color: .indigo, centerX: 190, centerY: 420),
      shapeElement(
        id: baseID + 3, kind: .ellipse, color: .orange, centerX: 470, centerY: 500),
      shapeElement(id: baseID + 4, kind: .arrow, color: .teal, centerX: 350, centerY: 650),
      WorkspaceElement(
        id: fixedUUID(baseID + 5),
        kind: .image,
        frame: WorkspaceElementFrame(
          center: CGPoint(x: 300, y: 820),
          size: CGSize(width: 320, height: 220)),
        zIndex: 5,
        assetFilename: imageFilename,
        displayName: "Stress fixture illustration",
        aspectRatio: 4.0 / 3.0),
    ]
  }

  private static func shapeElement(
    id: Int,
    kind: WorkspaceShapeKind,
    color: WorkspaceElementColor,
    centerX: CGFloat,
    centerY: CGFloat
  ) -> WorkspaceElement {
    WorkspaceElement(
      id: fixedUUID(id),
      kind: .shape,
      frame: WorkspaceElementFrame(
        center: CGPoint(x: centerX, y: centerY),
        size: CGSize(width: 190, height: 120)),
      zIndex: id,
      shapeKind: kind,
      color: color)
  }

  private static func drawing(for index: Int) -> PKDrawing {
    PKDrawing(
      strokes: (0..<6).map { strokeIndex in
        stroke(pageIndex: index, strokeIndex: strokeIndex)
      })
  }

  private static func stroke(pageIndex: Int, strokeIndex: Int) -> PKStroke {
    let points = (0..<48).map { pointIndex in
      let horizontalPosition = CGFloat(65 + pointIndex * 12)
      let wave = (pointIndex + pageIndex + strokeIndex * 2) % 7
      let verticalPosition = CGFloat(220 + strokeIndex * 78 + wave * 5)
      return PKStrokePoint(
        location: CGPoint(x: horizontalPosition, y: verticalPosition),
        timeOffset: TimeInterval(pointIndex) / 120,
        size: CGSize(width: 4, height: 4),
        opacity: 1,
        force: 0.55,
        azimuth: 0,
        altitude: .pi / 2)
    }
    let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 0))
    let colors: [UIColor] = [.label, .systemBlue, .systemIndigo, .systemTeal]
    let color = colors[(pageIndex + strokeIndex) % colors.count]
    return PKStroke(ink: PKInk(.pen, color: color), path: path)
  }

  private static func fixtureImage(in directories: AppDirectories) throws -> URL {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 120))
    let image = renderer.image { context in
      UIColor.systemIndigo.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 160, height: 120))
      UIColor.systemOrange.setFill()
      UIBezierPath(ovalIn: CGRect(x: 22, y: 18, width: 76, height: 76)).fill()
      UIColor.white.setFill()
      UIBezierPath(roundedRect: CGRect(x: 92, y: 62, width: 52, height: 34), cornerRadius: 8)
        .fill()
    }
    guard let data = image.pngData() else { throw StressFixtureError.imageEncodingFailed }
    let url = directories.root.appending(path: "stress-fixture.png")
    try data.write(to: url, options: .atomic)
    return url
  }

  private static func fixedUUID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value)) ?? UUID()
  }
}

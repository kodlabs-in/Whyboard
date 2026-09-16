import CoreGraphics
import PDFKit
import PencilKit
import UIKit

enum PagePreviewLayout: Equatable, Sendable {
  case page
  case infiniteCanvas(contentSize: CGSize, emptyViewport: CGRect)

  init(noteKind: NoteKind) {
    switch noteKind {
    case .infinitePages:
      self = .page
    case .infiniteCanvas:
      self = .infiniteCanvas(
        contentSize: InfiniteCanvasMetrics.contentSize,
        emptyViewport: Self.defaultCanvasViewport)
    }
  }

  init(note: Note) {
    guard note.kind == .infiniteCanvas else {
      self = .page
      return
    }
    let zoom = max(note.canvasZoomScale ?? 1, Double(InfiniteCanvasMetrics.minimumZoomScale))
    let viewport = CGRect(
      x: note.canvasOffsetX ?? Self.defaultCanvasViewport.minX,
      y: note.canvasOffsetY ?? Self.defaultCanvasViewport.minY,
      width: 1_200 / zoom,
      height: 800 / zoom)
    self = .infiniteCanvas(
      contentSize: InfiniteCanvasMetrics.contentSize,
      emptyViewport: viewport)
  }

  nonisolated func sourceBounds(
    drawing: PKDrawing,
    elements: [WorkspaceElement]
  ) -> CGRect {
    switch self {
    case .page:
      CGRect(origin: .zero, size: CanonicalPage.size)
    case .infiniteCanvas(let contentSize, let emptyViewport):
      infiniteCanvasBounds(
        drawing: drawing,
        elements: elements,
        contentSize: contentSize,
        emptyViewport: emptyViewport)
    }
  }

  private nonisolated func infiniteCanvasBounds(
    drawing: PKDrawing,
    elements: [WorkspaceElement],
    contentSize: CGSize,
    emptyViewport: CGRect
  ) -> CGRect {
    let contentBounds = CGRect(origin: .zero, size: contentSize)
    let occupiedBounds = elements.reduce(drawing.bounds) { bounds, element in
      bounds.union(element.previewBounds)
    }
    guard !occupiedBounds.isNull, !occupiedBounds.isEmpty else {
      return emptyViewport.intersection(contentBounds)
    }
    return occupiedBounds.insetBy(dx: -80, dy: -80).intersection(contentBounds)
  }

  private static let defaultCanvasViewport = CGRect(
    x: InfiniteCanvasMetrics.contentSize.width / 2 - 600,
    y: InfiniteCanvasMetrics.contentSize.height / 2 - 400,
    width: 1_200,
    height: 800)
}

struct PagePreviewDescriptor: Equatable, Sendable {
  let noteID: UUID
  let pageID: UUID
  let revision: Int64
  let elements: [WorkspaceElement]
  let layout: PagePreviewLayout
  let paperStyle: NotePaperStyle
  let background: ImportedPDFBackground?

  init(
    page: Page,
    noteKind: NoteKind,
    paperStyle: NotePaperStyle = .white
  ) {
    noteID = page.noteID
    pageID = page.id
    revision = page.contentRevision
    elements = WorkspaceElementCoding.decode(page.workspaceElementsData)
    layout = PagePreviewLayout(noteKind: noteKind)
    self.paperStyle = paperStyle == .automatic ? .white : paperStyle
    background = ImportedPDFBackground(page: page)
  }

  init(page: Page, note: Note, paperStyle: NotePaperStyle = .white) {
    noteID = page.noteID
    pageID = page.id
    revision = page.contentRevision
    elements = WorkspaceElementCoding.decode(page.workspaceElementsData)
    layout = PagePreviewLayout(note: note)
    self.paperStyle = paperStyle == .automatic ? .white : paperStyle
    background = ImportedPDFBackground(page: page)
  }

  var taskID: String {
    "\(pageID.uuidString)-\(revision)-v\(PagePreviewRenderer.version)"
  }
}

struct PagePreviewSnapshot: Sendable {
  let drawing: PKDrawing
  let elements: [WorkspaceElement]
  let layout: PagePreviewLayout
  let paperStyle: NotePaperStyle
  let background: ImportedPDFBackground?
}

struct ImportedPDFBackground: Equatable, Sendable {
  let documentID: UUID
  let pageIndex: Int

  init?(page: Page) {
    guard
      let documentID = page.importedDocumentID,
      let pageIndex = page.importedDocumentPageIndex
    else { return nil }
    self.documentID = documentID
    self.pageIndex = pageIndex
  }
}

nonisolated struct PagePreviewRenderer: Sendable {
  static let version = 3

  private static let maximumPixelDimension: CGFloat = 640
  private static let openShapes: Set<WorkspaceShapeKind> = [.line, .arrow]
  private static let colors: [WorkspaceElementColor: UIColor] = [
    .graphite: UIColor(red: 0.18, green: 0.19, blue: 0.22, alpha: 1),
    .indigo: UIColor(red: 0.31, green: 0.36, blue: 0.91, alpha: 1),
    .blue: .systemBlue,
    .teal: .systemTeal,
    .green: .systemGreen,
    .yellow: .systemYellow,
    .orange: .systemOrange,
    .red: .systemRed,
    .pink: .systemPink,
    .purple: .systemPurple,
  ]
  private static let shapePaths: [WorkspaceShapeKind: @Sendable (CGRect) -> UIBezierPath] = [
    .rectangle: { UIBezierPath(roundedRect: $0.insetBy(dx: 5, dy: 5), cornerRadius: 18) },
    .ellipse: { UIBezierPath(ovalIn: $0.insetBy(dx: 5, dy: 5)) },
    .triangle: { rect in
      let path = UIBezierPath()
      path.move(to: CGPoint(x: rect.midX, y: rect.minY + 5))
      path.addLine(to: CGPoint(x: rect.maxX - 5, y: rect.maxY - 5))
      path.addLine(to: CGPoint(x: rect.minX + 5, y: rect.maxY - 5))
      path.close()
      return path
    },
    .line: { rect in
      let path = UIBezierPath()
      path.move(to: CGPoint(x: rect.minX + 8, y: rect.maxY - 8))
      path.addLine(to: CGPoint(x: rect.maxX - 8, y: rect.minY + 8))
      return path
    },
    .arrow: { rect in
      let path = UIBezierPath()
      let end = CGPoint(x: rect.maxX - 8, y: rect.midY)
      path.move(to: CGPoint(x: rect.minX + 8, y: rect.midY))
      path.addLine(to: end)
      path.move(to: CGPoint(x: end.x - 28, y: end.y - 22))
      path.addLine(to: end)
      path.addLine(to: CGPoint(x: end.x - 28, y: end.y + 22))
      return path
    },
  ]

  let attachments: AttachmentRepository
  let documents: DocumentRepository

  func render(_ snapshot: PagePreviewSnapshot, noteID: UUID, pageID: UUID) -> UIImage {
    let bounds = snapshot.layout.sourceBounds(
      drawing: snapshot.drawing,
      elements: snapshot.elements)
    let outputSize = Self.outputSize(for: bounds.size)
    let outputScale = outputSize.width / bounds.width
    let format = UIGraphicsImageRendererFormat()
    format.opaque = false
    format.scale = 1

    return UIGraphicsImageRenderer(size: outputSize, format: format).image { context in
      configure(context.cgContext, sourceBounds: bounds, outputScale: outputScale)
      drawLayers(
        snapshot,
        noteID: noteID,
        pageID: pageID,
        sourceBounds: bounds,
        drawingScale: outputScale)
    }
  }

  func drawForExport(
    _ snapshot: PagePreviewSnapshot,
    noteID: UUID,
    pageID: UUID,
    in context: CGContext,
    outputSize: CGSize
  ) {
    let sourceBounds = snapshot.layout.sourceBounds(
      drawing: snapshot.drawing,
      elements: snapshot.elements)
    let scale = min(
      outputSize.width / sourceBounds.width,
      outputSize.height / sourceBounds.height)
    let fittedSize = CGSize(
      width: sourceBounds.width * scale,
      height: sourceBounds.height * scale)
    let offset = CGPoint(
      x: (outputSize.width - fittedSize.width) / 2,
      y: (outputSize.height - fittedSize.height) / 2)

    context.saveGState()
    context.translateBy(x: offset.x, y: offset.y)
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: -sourceBounds.minX, y: -sourceBounds.minY)
    UIGraphicsPushContext(context)
    drawLayers(
      snapshot,
      noteID: noteID,
      pageID: pageID,
      sourceBounds: sourceBounds,
      drawingScale: scale)
    UIGraphicsPopContext()
    context.restoreGState()
  }

  private func configure(
    _ context: CGContext,
    sourceBounds: CGRect,
    outputScale: CGFloat
  ) {
    context.scaleBy(x: outputScale, y: outputScale)
    context.translateBy(x: -sourceBounds.minX, y: -sourceBounds.minY)
  }

  private func drawElements(
    _ elements: [WorkspaceElement],
    noteID: UUID,
    pageID: UUID
  ) {
    for element in elements.sorted(by: { $0.zIndex < $1.zIndex }) {
      draw(element, noteID: noteID, pageID: pageID)
    }
  }

  private func drawLayers(
    _ snapshot: PagePreviewSnapshot,
    noteID: UUID,
    pageID: UUID,
    sourceBounds: CGRect,
    drawingScale: CGFloat
  ) {
    Self.paperColor(snapshot.paperStyle).setFill()
    UIRectFill(sourceBounds)
    drawPDFBackground(snapshot.background, noteID: noteID, in: sourceBounds)
    drawElements(snapshot.elements, noteID: noteID, pageID: pageID)
    draw(snapshot.drawing, in: sourceBounds, scale: drawingScale)
  }

  private func drawPDFBackground(
    _ background: ImportedPDFBackground?,
    noteID: UUID,
    in bounds: CGRect
  ) {
    guard
      let background,
      let document = PDFDocument(
        url: documents.fileURL(noteID: noteID, documentID: background.documentID)),
      let page = document.page(at: background.pageIndex),
      let context = UIGraphicsGetCurrentContext()
    else { return }
    let source = page.bounds(for: .mediaBox)
    let destination = Self.aspectFit(source.size, inside: bounds)
    context.saveGState()
    context.translateBy(x: destination.minX, y: destination.maxY)
    context.scaleBy(
      x: destination.width / source.width,
      y: -destination.height / source.height)
    context.translateBy(x: -source.minX, y: -source.minY)
    page.draw(with: .mediaBox, to: context)
    context.restoreGState()
  }

  private func draw(_ element: WorkspaceElement, noteID: UUID, pageID: UUID) {
    guard let context = UIGraphicsGetCurrentContext() else { return }
    context.saveGState()
    context.translateBy(x: element.frame.center.x, y: element.frame.center.y)
    context.rotate(by: CGFloat(element.frame.rotationDegrees * .pi / 180))
    let bounds = CGRect(
      x: -element.frame.size.width / 2,
      y: -element.frame.size.height / 2,
      width: element.frame.size.width,
      height: element.frame.size.height)

    switch element.kind {
    case .text:
      drawText(element, in: bounds)
    case .shape:
      drawShape(element, in: bounds)
    case .image:
      drawImage(element, in: bounds, noteID: noteID, pageID: pageID)
    }
    context.restoreGState()
  }

  private func drawText(_ element: WorkspaceElement, in bounds: CGRect) {
    let attributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: 28, weight: .medium),
      .foregroundColor: Self.color(for: element.color),
    ]
    NSString(string: element.displayText).draw(
      with: bounds.insetBy(dx: 12, dy: 12),
      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
      attributes: attributes,
      context: nil)
  }

  private func drawShape(_ element: WorkspaceElement, in bounds: CGRect) {
    let kind = element.shapeKind ?? .rectangle
    guard let path = Self.shapePaths[kind]?(bounds) else { return }
    let color = Self.color(for: element.color)
    path.lineWidth = kind == .line || kind == .arrow ? 6 : 5
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    color.setStroke()
    if !Self.openShapes.contains(kind) {
      color.withAlphaComponent(0.14).setFill()
      path.fill()
    }
    path.stroke()
  }

  private func drawImage(
    _ element: WorkspaceElement,
    in bounds: CGRect,
    noteID: UUID,
    pageID: UUID
  ) {
    guard let filename = element.assetFilename else { return }
    let url = attachments.fileURL(noteID: noteID, pageID: pageID, filename: filename)
    guard
      let image = AttachmentImageDecoder.image(
        at: url,
        maximumPixelDimension: 2_048)
    else { return }
    UIBezierPath(roundedRect: bounds, cornerRadius: 14).addClip()
    image.draw(in: Self.aspectFit(image.size, inside: bounds))
  }

  private func draw(_ drawing: PKDrawing, in bounds: CGRect, scale: CGFloat) {
    drawing.image(from: bounds, scale: scale).draw(in: bounds)
  }

  private static func outputSize(for sourceSize: CGSize) -> CGSize {
    guard sourceSize.width > 0, sourceSize.height > 0 else {
      return CGSize(width: 1, height: 1)
    }
    let scale = maximumPixelDimension / max(sourceSize.width, sourceSize.height)
    return CGSize(
      width: max(1, (sourceSize.width * scale).rounded(.up)),
      height: max(1, (sourceSize.height * scale).rounded(.up)))
  }

  private static func aspectFit(_ imageSize: CGSize, inside bounds: CGRect) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
    let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
    let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    return CGRect(
      x: bounds.midX - size.width / 2,
      y: bounds.midY - size.height / 2,
      width: size.width,
      height: size.height)
  }

  private static func color(for color: WorkspaceElementColor) -> UIColor {
    colors[color, default: .systemIndigo]
  }

}

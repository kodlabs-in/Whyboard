import PDFKit
import SwiftUI

struct ImportedPDFPageView: UIViewRepresentable {
  let noteID: UUID
  let documentID: UUID
  let pageIndex: Int
  let documents: DocumentRepository

  func makeUIView(context: Context) -> ImportedPDFPageUIView {
    ImportedPDFPageUIView()
  }

  func updateUIView(_ view: ImportedPDFPageUIView, context: Context) {
    view.configure(
      url: documents.fileURL(noteID: noteID, documentID: documentID),
      pageIndex: pageIndex)
  }
}

final class ImportedPDFPageUIView: UIView {
  private var page: PDFPage?
  private var configurationID = ""

  override static var layerClass: AnyClass { CATiledLayer.self }

  override init(frame: CGRect) {
    super.init(frame: frame)
    isOpaque = true
    backgroundColor = .white
    contentMode = .redraw
    if let tiledLayer = layer as? CATiledLayer {
      tiledLayer.levelsOfDetail = 4
      tiledLayer.levelsOfDetailBias = 3
      tiledLayer.tileSize = CGSize(width: 512, height: 512)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(url: URL, pageIndex: Int) {
    let nextID = "\(url.path)#\(pageIndex)"
    guard nextID != configurationID else { return }
    configurationID = nextID
    page = PDFDocument(url: url)?.page(at: pageIndex)
    setNeedsDisplay()
  }

  override func draw(_ rect: CGRect) {
    guard let page, let context = UIGraphicsGetCurrentContext() else { return }
    UIColor.white.setFill()
    context.fill(rect)
    let source = page.bounds(for: .mediaBox)
    let destination = aspectFit(source.size, inside: bounds)
    context.saveGState()
    context.translateBy(x: destination.minX, y: destination.maxY)
    context.scaleBy(
      x: destination.width / source.width,
      y: -destination.height / source.height)
    context.translateBy(x: -source.minX, y: -source.minY)
    page.draw(with: .mediaBox, to: context)
    context.restoreGState()
  }

  private func aspectFit(_ size: CGSize, inside bounds: CGRect) -> CGRect {
    guard size.width > 0, size.height > 0 else { return bounds }
    let scale = min(bounds.width / size.width, bounds.height / size.height)
    let fitted = CGSize(width: size.width * scale, height: size.height * scale)
    return CGRect(
      x: bounds.midX - fitted.width / 2,
      y: bounds.midY - fitted.height / 2,
      width: fitted.width,
      height: fitted.height)
  }
}

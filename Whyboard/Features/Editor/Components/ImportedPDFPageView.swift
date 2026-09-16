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
  private let pdfView = PDFView()
  private var configurationID = ""

  override init(frame: CGRect) {
    super.init(frame: frame)
    isOpaque = true
    backgroundColor = .white
    configurePDFView()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(url: URL, pageIndex: Int) {
    let nextID = "\(url.path)#\(pageIndex)"
    guard nextID != configurationID else { return }
    guard
      let document = PDFDocument(url: url),
      let page = document.page(at: pageIndex)
    else {
      configurationID = ""
      pdfView.document = nil
      return
    }
    configurationID = nextID
    pdfView.document = document
    pdfView.go(to: page)
    pdfView.autoScales = true
  }

  private func configurePDFView() {
    pdfView.frame = bounds
    pdfView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    pdfView.backgroundColor = .white
    pdfView.displayBox = .mediaBox
    pdfView.displayMode = .singlePage
    pdfView.displayDirection = .vertical
    pdfView.displaysPageBreaks = false
    pdfView.pageShadowsEnabled = false
    pdfView.isUserInteractionEnabled = false
    pdfView.autoScales = true
    addSubview(pdfView)
  }
}

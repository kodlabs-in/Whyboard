import SwiftUI

struct JumpToPageSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var pageNumber: String

  let note: Note
  let pages: [Page]
  let drawingRepository: DrawingRepository
  let onSelect: (UUID) -> Void

  init(
    note: Note,
    pages: [Page],
    currentPageID: UUID?,
    drawingRepository: DrawingRepository,
    onSelect: @escaping (UUID) -> Void
  ) {
    self.note = note
    self.pages = pages
    self.drawingRepository = drawingRepository
    self.onSelect = onSelect
    _pageNumber = State(
      initialValue: "\(PageNavigation.number(of: currentPageID, in: pages))")
  }

  private var requestedPage: Page? {
    guard let number = Int(pageNumber) else { return nil }
    return PageNavigation.page(number: number, in: pages)
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        pageNumberEntry
        Divider()
        pageList
      }
      .navigationTitle("Jump to Page")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: dismiss.callAsFunction)
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  private var pageNumberEntry: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        TextField("Page number", text: $pageNumber)
          .keyboardType(.numberPad)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier("jump-to-page-field")
          .onSubmit(jumpToEnteredPage)

        Button("Go", action: jumpToEnteredPage)
          .buttonStyle(.borderedProminent)
          .disabled(requestedPage == nil)
          .accessibilityIdentifier("jump-to-page-go")
      }

      Text(validationMessage)
        .font(.caption)
        .foregroundStyle(requestedPage == nil ? .red : .secondary)
    }
    .padding(20)
  }

  private var pageList: some View {
    List {
      ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
        Button {
          select(page)
        } label: {
          HStack(spacing: 14) {
            PageThumbnailView(
              note: note,
              page: page,
              pageNumber: index + 1,
              drawingRepository: drawingRepository
            )
            .frame(width: 64)
            Text("Page \(index + 1)")
              .font(.headline)
          }
        }
        .buttonStyle(.plain)
      }
    }
    .listStyle(.plain)
  }

  private var validationMessage: String {
    requestedPage == nil
      ? "Enter a page from 1 to \(pages.count)."
      : "\(pages.count) pages"
  }

  private func jumpToEnteredPage() {
    guard let requestedPage else { return }
    select(requestedPage)
  }

  private func select(_ page: Page) {
    onSelect(page.id)
    dismiss()
  }
}

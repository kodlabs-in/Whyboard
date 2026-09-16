import SwiftUI

struct PageOrganizerSheet: View {
  @Environment(\.dismiss) private var dismiss

  let note: Note
  let pages: [Page]
  let currentPageID: UUID?
  let drawingRepository: DrawingRepository
  let onSelect: (UUID) -> Void
  let onMove: (IndexSet, Int) -> Void

  var body: some View {
    NavigationStack {
      List {
        ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
          Button {
            onSelect(page.id)
            dismiss()
          } label: {
            HStack(spacing: 14) {
              PageThumbnailView(
                note: note,
                page: page,
                pageNumber: index + 1,
                drawingRepository: drawingRepository,
                isSelected: page.id == currentPageID
              )
              .frame(width: 74)

              Text("Page \(index + 1)")
                .font(.headline)

              Spacer()
              if page.id == currentPageID {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(WhyboardTheme.accent)
                  .accessibilityHidden(true)
              }
            }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("page-organizer-page-\(index + 1)")
        }
        .onMove(perform: onMove)
      }
      .environment(\.editMode, .constant(.active))
      .navigationTitle("Pages")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }
}

import SwiftUI

struct PageOrganizerSheet: View {
  @Environment(\.dismiss) private var dismiss

  let pages: [Page]
  let onMove: (IndexSet, Int) -> Void

  var body: some View {
    NavigationStack {
      List {
        ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
          HStack(spacing: 14) {
            Image(systemName: "doc.plaintext")
              .foregroundStyle(WhyboardTheme.accent)
            Text("Page \(index + 1)")
            Spacer()
            Text("Revision \(page.contentRevision)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .onMove(perform: onMove)
      }
      .environment(\.editMode, .constant(.active))
      .navigationTitle("Arrange Pages")
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

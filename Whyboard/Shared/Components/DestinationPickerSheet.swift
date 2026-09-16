import SwiftUI

struct DestinationPickerRequest: Identifiable {
  let id = UUID()
  let title: String
  let destinations: [FolderDestination]
  let currentFolderID: UUID?
  var allowsCurrentDestination = false
  let onSelect: (Folder?) -> Void
}

struct DestinationPickerSheet: View {
  @Environment(\.dismiss) private var dismiss

  let request: DestinationPickerRequest

  var body: some View {
    NavigationStack {
      List(request.destinations) { destination in
        Button {
          request.onSelect(destination.folder)
          dismiss()
        } label: {
          destinationRow(destination)
        }
        .buttonStyle(.plain)
        .disabled(
          !request.allowsCurrentDestination
            && destination.folder?.id == request.currentFolderID)
      }
      .navigationTitle(request.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", role: .cancel) { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  private func destinationRow(_ destination: FolderDestination) -> some View {
    HStack(spacing: 12) {
      Color.clear.frame(width: CGFloat(destination.depth) * 18)
      Image(systemName: destination.folder == nil ? "books.vertical" : "folder")
        .foregroundStyle(WhyboardTheme.accent)
      Text(destination.folder?.name ?? "Library")
      Spacer()
      if destination.folder?.id == request.currentFolderID {
        Image(systemName: "checkmark")
          .foregroundStyle(.secondary)
      }
    }
    .contentShape(Rectangle())
  }
}

import SwiftUI

struct NoteListView: View {
  let title: String
  let notes: [Note]
  let pageCounts: [UUID: Int]
  @Binding var selection: UUID?
  @Binding var searchText: String
  let onCreateNote: () -> Void
  let onRenameNote: (Note) -> Void
  let onMoveNote: (Note) -> Void
  let onDeleteNote: (Note) -> Void

  var body: some View {
    List(selection: $selection) {
      ForEach(notes) { note in
        NoteRow(note: note, pageCount: pageCounts[note.id, default: 0])
          .tag(note.id)
          .contextMenu {
            noteActions(note)
          }
      }
    }
    .overlay {
      if notes.isEmpty {
        emptyState
      }
    }
    .navigationTitle(title)
    .searchable(text: $searchText, prompt: "Search notes")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("New Note", systemImage: "square.and.pencil", action: onCreateNote)
          .accessibilityHint("Creates a note with one blank page")
      }
    }
  }

  private var emptyState: some View {
    ContentUnavailableView {
      Label(
        searchText.isEmpty ? "No Notes Yet" : "No Matching Notes",
        systemImage: searchText.isEmpty ? "note.text.badge.plus" : "magnifyingglass")
    } description: {
      Text(
        searchText.isEmpty
          ? "Create a note and start writing with Apple Pencil."
          : "Try a different title.")
    } actions: {
      if searchText.isEmpty {
        Button("New Note", action: onCreateNote)
          .buttonStyle(.borderedProminent)
      }
    }
  }

  @ViewBuilder
  private func noteActions(_ note: Note) -> some View {
    Button("Rename", systemImage: "pencil") { onRenameNote(note) }
    Button("Move", systemImage: "folder") { onMoveNote(note) }
    Divider()
    Button("Delete", systemImage: "trash", role: .destructive) {
      onDeleteNote(note)
    }
  }
}

import SwiftUI

struct NoteOptionsMenu: View {
  @Binding var paperStyle: NotePaperStyle
  @Binding var drawsWithFinger: Bool

  let onRename: () -> Void
  var onDuplicate: (() -> Void)?
  var onExportPDF: (() -> Void)?
  var onPreviousPage: (() -> Void)?
  var onNextPage: (() -> Void)?

  var body: some View {
    Menu("Note Options", systemImage: "ellipsis.circle") {
      Button("Rename Note", systemImage: "pencil", action: onRename)
      if let onDuplicate {
        Button("Duplicate Page", systemImage: "plus.square.on.square", action: onDuplicate)
          .keyboardShortcut("d", modifiers: .command)
      }
      if let onExportPDF {
        Button("Export PDF", systemImage: "square.and.arrow.up", action: onExportPDF)
          .keyboardShortcut("p", modifiers: .command)
      }
      if let onPreviousPage {
        Button("Previous Page", systemImage: "arrow.left", action: onPreviousPage)
          .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
      }
      if let onNextPage {
        Button("Next Page", systemImage: "arrow.right", action: onNextPage)
          .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
      }
      Divider()
      Picker("Background Color", selection: $paperStyle) {
        ForEach(NotePaperStyle.selectableStyles) { style in
          Text(style.name).tag(style)
        }
      }
      Toggle("Draw with Finger", isOn: $drawsWithFinger)
    }
  }
}

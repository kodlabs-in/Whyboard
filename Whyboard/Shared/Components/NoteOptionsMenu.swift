import SwiftUI

struct NoteOptionsMenu: View {
  @Binding var paperStyle: NotePaperStyle
  @Binding var drawsWithFinger: Bool

  let onRename: () -> Void

  var body: some View {
    Menu("Note Options", systemImage: "ellipsis.circle") {
      Button("Rename Note", systemImage: "pencil", action: onRename)
      Picker("Paper Color", selection: $paperStyle) {
        ForEach(NotePaperStyle.allCases) { style in
          Text(style.name).tag(style)
        }
      }
      Toggle("Draw with Finger", isOn: $drawsWithFinger)
    }
  }
}

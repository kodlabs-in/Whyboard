import SwiftUI

struct EditorAddPageButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label("Add Page", systemImage: "plus")
        .font(.headline)
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
    }
    .buttonStyle(.borderedProminent)
    .buttonBorderShape(.capsule)
    .padding(.bottom, 40)
    .accessibilityHint("Appends a blank page to this note")
  }
}

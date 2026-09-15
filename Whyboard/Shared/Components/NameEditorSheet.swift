import SwiftUI

struct NameEditorRequest: Identifiable {
  let id = UUID()
  let title: String
  let prompt: String
  let initialName: String
  let systemImage: String
  let onSave: (String) -> Void
}

struct NameEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var name: String

  let request: NameEditorRequest

  init(request: NameEditorRequest) {
    self.request = request
    _name = State(initialValue: request.initialName)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          HStack {
            Spacer()
            Image(systemName: request.systemImage)
              .font(.system(size: 34, weight: .medium))
              .foregroundStyle(WhyboardTheme.accent)
              .padding(.vertical, 4)
            Spacer()
          }
          .listRowBackground(Color.clear)
        }

        Section(request.prompt) {
          TextField("Name", text: $name)
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .onSubmit(save)
        }
      }
      .navigationTitle(request.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", role: .cancel) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", action: save)
            .disabled(trimmedName.isEmpty)
        }
      }
    }
    .presentationDetents([.height(300)])
    .presentationDragIndicator(.visible)
  }

  private var trimmedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func save() {
    guard !trimmedName.isEmpty else { return }
    request.onSave(trimmedName)
    dismiss()
  }
}

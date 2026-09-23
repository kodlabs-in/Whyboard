import SwiftUI

struct WorkspaceObjectToolbar: View {
  let controller: WorkspaceElementEditingController

  var body: some View {
    HStack(spacing: 12) {
      Button(
        controller.interactionMode.actionName,
        systemImage: controller.interactionMode.systemImage,
        action: controller.toggleInteractionMode
      )
      .tint(controller.interactionMode == .arrange ? .orange : WhyboardTheme.accent)

      WorkspaceInsertMenu(
        onAddText: controller.addText,
        onAddShape: controller.addShape,
        onAddPhoto: controller.presentPhotoPicker,
        onAddImageFile: controller.presentFileImporter)

      WorkspaceElementActionsMenu(
        element: controller.selectedElement,
        onEdit: controller.editSelectedText,
        onPreview: controller.previewSelectedMedia,
        onSetColor: controller.setSelectedColor,
        onDuplicate: controller.duplicateSelected,
        onBringToFront: controller.bringSelectedToFront,
        onSendToBack: controller.sendSelectedToBack,
        onDelete: controller.deleteSelected)
    }
  }
}

struct WorkspaceInsertMenu: View {
  let onAddText: () -> Void
  let onAddShape: (WorkspaceShapeKind) -> Void
  let onAddPhoto: () -> Void
  let onAddImageFile: () -> Void

  var body: some View {
    Menu("Insert", systemImage: "plus.square.on.square") {
      Button("Text", systemImage: "textformat", action: onAddText)

      Menu("Shape", systemImage: "square.on.circle") {
        ForEach(WorkspaceShapeKind.allCases) { shape in
          Button(shape.name, systemImage: shape.systemImage) {
            onAddShape(shape)
          }
        }
      }

      Divider()
      Button("Photo", systemImage: "photo.on.rectangle", action: onAddPhoto)
      Button("Image File", systemImage: "folder", action: onAddImageFile)
    }
  }
}

struct WorkspaceElementActionsMenu: View {
  let element: WorkspaceElement?
  let onEdit: () -> Void
  let onPreview: () -> Void
  let onSetColor: (WorkspaceElementColor) -> Void
  let onDuplicate: () -> Void
  let onBringToFront: () -> Void
  let onSendToBack: () -> Void
  let onDelete: () -> Void

  var body: some View {
    Menu("Object Actions", systemImage: "slider.horizontal.3") {
      if let element {
        primaryActions(for: element)
        Divider()
        Button("Duplicate", systemImage: "plus.square.on.square", action: onDuplicate)
        Button(
          "Bring to Front", systemImage: "square.3.layers.3d.top.filled", action: onBringToFront)
        Button(
          "Send to Back", systemImage: "square.3.layers.3d.bottom.filled", action: onSendToBack)
        Divider()
        Button("Delete Object", systemImage: "trash", role: .destructive, action: onDelete)
          .keyboardShortcut(.delete, modifiers: [])
          .accessibilityIdentifier("workspace-delete-object")
      } else {
        Text("Select an object in Arrange mode")
      }
    }
    .disabled(element == nil)
  }

  @ViewBuilder
  private func primaryActions(for element: WorkspaceElement) -> some View {
    if element.kind == .text {
      Button("Edit Text", systemImage: "character.cursor.ibeam", action: onEdit)
    }

    if element.kind == .image {
      Button("Preview Photo", systemImage: "photo", action: onPreview)
    }

    if element.kind == .text || element.kind == .shape {
      Menu("Color", systemImage: "paintpalette") {
        ForEach(WorkspaceElementColor.allCases) { color in
          Button {
            onSetColor(color)
          } label: {
            Label(
              color.name,
              systemImage: color == element.color && element.textColor == nil
                ? "checkmark.circle.fill" : "circle.fill")
          }
        }
      }
    }
  }
}

struct TextElementEditorRequest: Identifiable {
  let id: UUID
  let initialText: String
  let initialFontSize: Double
  let initialColor: Color
  let onSave: (String, Double, WorkspaceTextColor) -> Void
}

struct TextElementEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var text: String
  @State private var fontSizeInput: String
  @State private var textColor: Color

  let request: TextElementEditorRequest

  init(request: TextElementEditorRequest) {
    self.request = request
    _text = State(initialValue: request.initialText)
    _fontSizeInput = State(initialValue: String(Int(request.initialFontSize.rounded())))
    _textColor = State(initialValue: request.initialColor)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Text") {
          TextEditor(text: $text)
            .frame(minHeight: 140)
        }
        Section("Style") {
          HStack {
            Text("Size (pt, 8–144)")
            Spacer()
            TextField("Size", text: $fontSizeInput)
              .keyboardType(.numberPad)
              .multilineTextAlignment(.trailing)
              .frame(width: 72)
              .accessibilityIdentifier("text-font-size")
          }
          ColorPicker("Text Color", selection: $textColor, supportsOpacity: true)
            .accessibilityIdentifier("text-color-picker")
        }
      }
      .navigationTitle("Edit Text")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: dismiss.callAsFunction)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", action: save)
            .disabled(validFontSize == nil)
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  private var validFontSize: Double? {
    guard let size = Int(fontSizeInput), (8...144).contains(size) else { return nil }
    return Double(size)
  }

  private func save() {
    guard let size = validFontSize else { return }
    request.onSave(
      text.trimmingCharacters(in: .whitespacesAndNewlines),
      size,
      WorkspaceTextColor(textColor))
    dismiss()
  }
}

struct WorkspaceElementEditingModifier: ViewModifier {
  @Bindable var controller: WorkspaceElementEditingController

  func body(content: Content) -> some View {
    content
      .workspaceMediaImport(controller.mediaImportController)
      .sheet(item: $controller.textEditorRequest) { request in
        TextElementEditorSheet(request: request)
      }
      .sheet(item: $controller.mediaPreviewRequest) { request in
        MediaPreviewSheet(request: request)
      }
  }
}

extension View {
  func workspaceElementEditing(_ controller: WorkspaceElementEditingController) -> some View {
    modifier(WorkspaceElementEditingModifier(controller: controller))
  }
}

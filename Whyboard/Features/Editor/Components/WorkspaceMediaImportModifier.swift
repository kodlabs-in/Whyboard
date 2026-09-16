import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceMediaImportModifier: ViewModifier {
  @Bindable var controller: MediaImportController

  func body(content: Content) -> some View {
    content
      .photosPicker(
        isPresented: $controller.isPhotoPickerPresented,
        selection: $controller.selectedPhotoItem,
        matching: .images
      )
      .fileImporter(
        isPresented: $controller.isFileImporterPresented,
        allowedContentTypes: [.image]
      ) { result in
        Task { await controller.importFile(result) }
      }
      .onChange(of: controller.selectedPhotoItem) { _, item in
        guard item != nil else { return }
        Task { await controller.importSelectedPhoto() }
      }
      .overlay(alignment: .top) {
        if controller.isImporting {
          Label("Adding photo…", systemImage: "arrow.down.circle")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, 12)
        }
      }
  }
}

extension View {
  func workspaceMediaImport(_ controller: MediaImportController) -> some View {
    modifier(WorkspaceMediaImportModifier(controller: controller))
  }
}

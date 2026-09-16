import QuickLook
import SwiftUI

struct MediaPreviewRequest: Identifiable {
  let id = UUID()
  let url: URL
  let title: String
}

struct MediaPreviewSheet: View {
  @Environment(\.dismiss) private var dismiss

  let request: MediaPreviewRequest

  var body: some View {
    NavigationStack {
      QuickLookPreview(url: request.url)
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(request.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done", action: dismiss.callAsFunction)
          }
        }
    }
  }
}

private struct QuickLookPreview: UIViewControllerRepresentable {
  let url: URL

  func makeCoordinator() -> Coordinator {
    Coordinator(url: url)
  }

  func makeUIViewController(context: Context) -> QLPreviewController {
    let controller = QLPreviewController()
    controller.dataSource = context.coordinator
    return controller
  }

  func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

  final class Coordinator: NSObject, QLPreviewControllerDataSource {
    let url: NSURL

    init(url: URL) {
      self.url = url as NSURL
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
      1
    }

    func previewController(
      _ controller: QLPreviewController,
      previewItemAt index: Int
    ) -> QLPreviewItem {
      url
    }
  }
}

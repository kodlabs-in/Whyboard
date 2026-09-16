import SwiftUI
import UIKit

struct WorkspaceTransform: Equatable {
  let scale: CGFloat
  let contentOffset: CGPoint

  static let identity = WorkspaceTransform(scale: 1, contentOffset: .zero)

  func screenFrame(for element: WorkspaceElement) -> CGRect {
    CGRect(
      x: CGFloat(element.frame.centerX - element.frame.width / 2) * scale - contentOffset.x,
      y: CGFloat(element.frame.centerY - element.frame.height / 2) * scale - contentOffset.y,
      width: CGFloat(element.frame.width) * scale,
      height: CGFloat(element.frame.height) * scale)
  }

  func isVisible(_ element: WorkspaceElement, in viewportSize: CGSize) -> Bool {
    let viewport = CGRect(origin: .zero, size: viewportSize).insetBy(dx: -80, dy: -80)
    return screenFrame(for: element).intersects(viewport)
  }
}

struct WorkspaceElementVisualLayer: View {
  let elements: [WorkspaceElement]
  let noteID: UUID
  let pageID: UUID
  let attachments: AttachmentRepository
  let transform: WorkspaceTransform
  let onImageAspectRatio: (UUID, Double) -> Void

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .topLeading) {
        ForEach(visibleElements(in: geometry.size)) { element in
          elementView(element)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .clipped()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func visibleElements(in viewportSize: CGSize) -> [WorkspaceElement] {
    elements
      .filter { transform.isVisible($0, in: viewportSize) }
      .sorted { $0.zIndex < $1.zIndex }
  }

  private func elementView(_ element: WorkspaceElement) -> some View {
    let frame = transform.screenFrame(for: element)
    let assetURL = element.assetFilename.map {
      attachments.fileURL(noteID: noteID, pageID: pageID, filename: $0)
    }

    return WorkspaceElementVisual(
      element: element,
      assetURL: assetURL,
      onImageAspectRatio: onImageAspectRatio
    )
    .frame(width: CGFloat(element.frame.width), height: CGFloat(element.frame.height))
    .rotationEffect(.degrees(element.frame.rotationDegrees))
    .scaleEffect(transform.scale)
    .position(x: frame.midX, y: frame.midY)
    .zIndex(Double(element.zIndex))
  }
}

private struct WorkspaceElementVisual: View {
  let element: WorkspaceElement
  let assetURL: URL?
  let onImageAspectRatio: (UUID, Double) -> Void

  var body: some View {
    Group {
      if element.kind == .text {
        textContent
      } else if element.kind == .shape {
        WorkspaceShapeView(
          kind: element.shapeKind ?? .rectangle,
          color: element.color.swiftUIColor)
      } else {
        WorkspaceImageView(url: assetURL) { aspectRatio in
          onImageAspectRatio(element.id, aspectRatio)
        }
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  private var textContent: some View {
    Text(element.displayText)
      .font(.system(size: 28, weight: .medium, design: .rounded))
      .foregroundStyle(element.color.swiftUIColor)
      .multilineTextAlignment(.leading)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(12)
  }
}

private struct WorkspaceShapeView: View {
  static let openShapes: Set<WorkspaceShapeKind> = [.line, .arrow]
  static let pathBuilders: [WorkspaceShapeKind: (CGRect) -> Path] = [
    .rectangle: { rect in
      Path(roundedRect: rect.insetBy(dx: 5, dy: 5), cornerRadius: 18)
    },
    .ellipse: { rect in
      Path(ellipseIn: rect.insetBy(dx: 5, dy: 5))
    },
    .triangle: { rect in
      var path = Path()
      path.move(to: CGPoint(x: rect.midX, y: rect.minY + 5))
      path.addLine(to: CGPoint(x: rect.maxX - 5, y: rect.maxY - 5))
      path.addLine(to: CGPoint(x: rect.minX + 5, y: rect.maxY - 5))
      path.closeSubpath()
      return path
    },
    .line: { rect in
      var path = Path()
      path.move(to: CGPoint(x: rect.minX + 8, y: rect.maxY - 8))
      path.addLine(to: CGPoint(x: rect.maxX - 8, y: rect.minY + 8))
      return path
    },
    .arrow: { rect in
      var path = Path()
      let start = CGPoint(x: rect.minX + 8, y: rect.midY)
      let end = CGPoint(x: rect.maxX - 8, y: rect.midY)
      path.move(to: start)
      path.addLine(to: end)
      path.move(to: CGPoint(x: end.x - 28, y: end.y - 22))
      path.addLine(to: end)
      path.addLine(to: CGPoint(x: end.x - 28, y: end.y + 22))
      return path
    },
  ]

  let kind: WorkspaceShapeKind
  let color: Color

  var body: some View {
    GeometryReader { geometry in
      let path = Self.pathBuilders[kind]?(geometry.frame(in: .local)) ?? Path()
      if Self.openShapes.contains(kind) {
        path.stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
      } else {
        path
          .fill(color.opacity(0.14))
          .overlay { path.stroke(color, lineWidth: 5) }
      }
    }
  }
}

private struct WorkspaceImageView: View {
  let url: URL?
  let onAspectRatio: (Double) -> Void

  @State private var image: UIImage?

  var body: some View {
    ZStack {
      Color.secondary.opacity(0.1)
      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
      } else {
        Image(systemName: "photo")
          .font(.largeTitle)
          .foregroundStyle(.secondary)
      }
    }
    .task(id: url) { await loadImage() }
  }

  private func loadImage() async {
    guard let url else { return }
    let data = await Task.detached(priority: .userInitiated) { try? Data(contentsOf: url) }.value
    guard let data else { return }
    guard let loadedImage = UIImage(data: data), loadedImage.size.height > 0 else { return }
    image = loadedImage
    onAspectRatio(Double(loadedImage.size.width / loadedImage.size.height))
  }
}

extension WorkspaceElementColor {
  private static let palette: [WorkspaceElementColor: Color] = [
    .graphite: Color(red: 0.18, green: 0.19, blue: 0.22),
    .indigo: WhyboardTheme.accent,
    .blue: .blue,
    .teal: .teal,
    .green: .green,
    .yellow: .yellow,
    .orange: .orange,
    .red: .red,
    .pink: .pink,
    .purple: .purple,
  ]

  var swiftUIColor: Color {
    Self.palette[self, default: WhyboardTheme.accent]
  }
}

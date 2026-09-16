import CoreGraphics
import Foundation

nonisolated enum WorkspaceElementKind: String, Codable, CaseIterable, Sendable {
  case text
  case shape
  case image
}

nonisolated enum WorkspaceShapeKind: String, Codable, CaseIterable, Identifiable, Sendable {
  case rectangle
  case ellipse
  case triangle
  case line
  case arrow

  var id: String { rawValue }

  private static let systemImages: [WorkspaceShapeKind: String] = [
    .rectangle: "rectangle",
    .ellipse: "circle",
    .triangle: "triangle",
    .line: "line.diagonal",
    .arrow: "arrow.right",
  ]

  var name: String { rawValue.capitalized }

  var systemImage: String {
    Self.systemImages[self, default: "rectangle"]
  }
}

nonisolated enum WorkspaceElementColor: String, Codable, CaseIterable, Identifiable, Sendable {
  case graphite
  case indigo
  case blue
  case teal
  case green
  case yellow
  case orange
  case red
  case pink
  case purple

  var id: String { rawValue }
  var name: String { rawValue.capitalized }
}

nonisolated struct WorkspaceElementFrame: Codable, Equatable, Sendable {
  var centerX: Double
  var centerY: Double
  var width: Double
  var height: Double
  var rotationDegrees: Double

  init(
    center: CGPoint,
    size: CGSize,
    rotationDegrees: Double = 0
  ) {
    centerX = Double(center.x)
    centerY = Double(center.y)
    width = Double(size.width)
    height = Double(size.height)
    self.rotationDegrees = rotationDegrees
  }

  nonisolated var center: CGPoint {
    CGPoint(x: centerX, y: centerY)
  }

  nonisolated var size: CGSize {
    CGSize(width: width, height: height)
  }

  func translated(by translation: CGSize, scale: CGFloat) -> WorkspaceElementFrame {
    var frame = self
    frame.centerX += Double(translation.width / scale)
    frame.centerY += Double(translation.height / scale)
    return frame
  }

  func resized(by translation: CGSize, scale: CGFloat) -> WorkspaceElementFrame {
    var frame = self
    frame.width = max(80, width + Double(translation.width / scale))
    frame.height = max(60, height + Double(translation.height / scale))
    return frame
  }

  func resizedPreservingAspectRatio(
    by translation: CGSize,
    scale: CGFloat
  ) -> WorkspaceElementFrame {
    let horizontalChange = Double(translation.width / scale)
    let verticalChange = Double(translation.height / scale)
    let squaredLength = width * width + height * height
    guard squaredLength > 0 else { return self }

    let projectedScale =
      1 + (horizontalChange * width + verticalChange * height) / squaredLength
    let minimumScale = max(80 / width, 60 / height)
    let resolvedScale = max(minimumScale, projectedScale)
    var frame = self
    frame.width = width * resolvedScale
    frame.height = height * resolvedScale
    return frame
  }

  static func aspectFittedSize(
    aspectRatio: Double,
    inside bounds: CGSize
  ) -> CGSize {
    guard aspectRatio.isFinite, aspectRatio > 0 else { return bounds }
    let boundsRatio = bounds.width / bounds.height
    if aspectRatio >= boundsRatio {
      return CGSize(width: bounds.width, height: bounds.width / aspectRatio)
    }
    return CGSize(width: bounds.height * aspectRatio, height: bounds.height)
  }

  func rotated(by degrees: Double) -> WorkspaceElementFrame {
    var frame = self
    frame.rotationDegrees = rotationDegrees + degrees
    return frame
  }

  func clamped(to canvasSize: CGSize) -> WorkspaceElementFrame {
    var frame = self
    let halfWidth = min(CGFloat(width / 2), canvasSize.width / 2)
    let halfHeight = min(CGFloat(height / 2), canvasSize.height / 2)
    frame.centerX = Double(min(max(CGFloat(centerX), halfWidth), canvasSize.width - halfWidth))
    frame.centerY = Double(min(max(CGFloat(centerY), halfHeight), canvasSize.height - halfHeight))
    return frame
  }
}

nonisolated struct WorkspaceElement: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  var kind: WorkspaceElementKind
  var frame: WorkspaceElementFrame
  var zIndex: Int
  var text: String?
  var shapeKind: WorkspaceShapeKind?
  var color: WorkspaceElementColor
  var assetFilename: String?
  var displayName: String?
  var aspectRatio: Double?

  init(
    id: UUID = UUID(),
    kind: WorkspaceElementKind,
    frame: WorkspaceElementFrame,
    zIndex: Int,
    text: String? = nil,
    shapeKind: WorkspaceShapeKind? = nil,
    color: WorkspaceElementColor = .indigo,
    assetFilename: String? = nil,
    displayName: String? = nil,
    aspectRatio: Double? = nil
  ) {
    self.id = id
    self.kind = kind
    self.frame = frame
    self.zIndex = zIndex
    self.text = text
    self.shapeKind = shapeKind
    self.color = color
    self.assetFilename = assetFilename
    self.displayName = displayName
    self.aspectRatio = aspectRatio
  }

  var accessibilityName: String {
    switch kind {
    case .text: "Text, \(displayText)"
    case .shape: shapeKind?.name ?? "Shape"
    case .image: "Photo, \(displayName ?? "Image")"
    }
  }

  nonisolated var displayText: String {
    guard let text, !text.isEmpty else { return "Double tap to add text" }
    return text
  }
}

nonisolated enum WorkspaceElementCoding {
  static func decode(_ data: Data?) -> [WorkspaceElement] {
    guard let data else { return [] }
    let decoded = try? JSONDecoder().decode([LossyWorkspaceElement].self, from: data)
    return decoded?.compactMap(\.value) ?? []
  }

  static func encode(_ elements: [WorkspaceElement]) throws -> Data? {
    guard !elements.isEmpty else { return nil }
    return try JSONEncoder().encode(elements)
  }
}

private nonisolated struct LossyWorkspaceElement: Decodable {
  let value: WorkspaceElement?

  init(from decoder: Decoder) throws {
    value = try? WorkspaceElement(from: decoder)
  }
}

extension WorkspaceElement {
  nonisolated var previewBounds: CGRect {
    let unrotated = CGRect(
      x: -frame.size.width / 2,
      y: -frame.size.height / 2,
      width: frame.size.width,
      height: frame.size.height)
    let transform = CGAffineTransform(translationX: frame.center.x, y: frame.center.y)
      .rotated(by: CGFloat(frame.rotationDegrees * .pi / 180))
    return unrotated.applying(transform)
  }
}

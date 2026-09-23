import CoreGraphics
import Foundation

nonisolated enum WorkspaceElementKind: String, Codable, CaseIterable, Sendable {
  case text
  case shape
  case image
}

nonisolated enum WorkspaceShapeKind: String, Codable, CaseIterable, Identifiable, Sendable {
  case rectangle
  case circle
  case ellipse
  case triangle
  case line
  case arrow

  var id: String { rawValue }

  private static let systemImages: [WorkspaceShapeKind: String] = [
    .rectangle: "rectangle",
    .circle: "circle",
    .ellipse: "circle",
    .triangle: "triangle",
    .line: "line.diagonal",
    .arrow: "arrow.right",
  ]

  var name: String { rawValue.capitalized }

  var systemImage: String {
    Self.systemImages[self, default: "rectangle"]
  }

  var defaultSize: CGSize {
    switch self {
    case .circle:
      CGSize(width: 200, height: 200)
    case .rectangle, .ellipse, .triangle, .line, .arrow:
      CGSize(width: 240, height: 180)
    }
  }

  var preservesAspectRatio: Bool {
    self == .circle
  }
}

nonisolated enum WorkspaceElementColor: String, Codable, CaseIterable, Identifiable, Sendable {
  case graphite
  case white
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

nonisolated struct WorkspaceTextColor: Codable, Equatable, Sendable {
  var red: Double
  var green: Double
  var blue: Double
  var opacity: Double

  static let white = WorkspaceTextColor(red: 1, green: 1, blue: 1, opacity: 1)

  init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
    self.red = red
    self.green = green
    self.blue = blue
    self.opacity = opacity
  }

  var isValid: Bool {
    [red, green, blue, opacity].allSatisfy { $0.isFinite && (0...1).contains($0) }
  }
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
    guard
      translation.width.isFinite,
      translation.height.isFinite,
      scale.isFinite,
      scale > 0
    else { return self }
    var frame = self
    frame.centerX += Double(translation.width / scale)
    frame.centerY += Double(translation.height / scale)
    return frame
  }

  func resized(by translation: CGSize, scale: CGFloat) -> WorkspaceElementFrame {
    guard
      translation.width.isFinite,
      translation.height.isFinite,
      scale.isFinite,
      scale > 0
    else { return self }
    var frame = self
    frame.width = max(80, width + Double(translation.width / scale))
    frame.height = max(60, height + Double(translation.height / scale))
    return frame
  }

  func resizedPreservingAspectRatio(
    by translation: CGSize,
    scale: CGFloat
  ) -> WorkspaceElementFrame {
    guard
      translation.width.isFinite,
      translation.height.isFinite,
      scale.isFinite,
      scale > 0,
      width.isFinite,
      height.isFinite
    else { return self }
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
    guard degrees.isFinite else { return self }
    var frame = self
    frame.rotationDegrees = rotationDegrees + degrees
    return frame
  }

  nonisolated var isValid: Bool {
    centerX.isFinite
      && centerY.isFinite
      && width.isFinite
      && height.isFinite
      && rotationDegrees.isFinite
      && width > 0
      && height > 0
  }

  func normalizedForPersistence() -> WorkspaceElementFrame? {
    guard isValid else { return nil }
    var frame = self
    frame.rotationDegrees = rotationDegrees.truncatingRemainder(dividingBy: 360)
    if frame.rotationDegrees < 0 {
      frame.rotationDegrees += 360
    }
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
  var fontSize: Double?
  var textColor: WorkspaceTextColor?
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
    fontSize: Double? = nil,
    textColor: WorkspaceTextColor? = nil,
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
    self.fontSize = fontSize
    self.textColor = textColor
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

  nonisolated var resolvedFontSize: Double { fontSize ?? 28 }

  nonisolated var isValidForPersistence: Bool {
    guard frame.isValid else { return false }
    if let fontSize, !fontSize.isFinite || !(8...144).contains(fontSize) { return false }
    if let textColor, !textColor.isValid { return false }
    guard let aspectRatio else { return true }
    return aspectRatio.isFinite && aspectRatio > 0
  }
}

nonisolated enum WorkspaceElementCodingError: LocalizedError, Equatable {
  case invalidGeometry(UUID)

  var errorDescription: String? {
    switch self {
    case .invalidGeometry:
      "Whyboard restored the previous object position because the new geometry was invalid."
    }
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
    if let invalidElement = elements.first(where: { !$0.isValidForPersistence }) {
      throw WorkspaceElementCodingError.invalidGeometry(invalidElement.id)
    }
    return try JSONEncoder().encode(elements)
  }
}

private nonisolated struct LossyWorkspaceElement: Decodable {
  let value: WorkspaceElement?

  init(from decoder: Decoder) throws {
    guard let decoded = try? WorkspaceElement(from: decoder), decoded.isValidForPersistence else {
      value = nil
      return
    }
    value = decoded
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

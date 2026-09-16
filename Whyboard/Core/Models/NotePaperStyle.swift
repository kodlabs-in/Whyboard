import Foundation

enum NotePaperStyle: String, CaseIterable, Identifiable, Sendable {
  case automatic
  case white
  case cream
  case black
  case softBlue

  static let defaultStorageKey = "defaultNotePaperStyle.v1"
  static let defaultStyle = NotePaperStyle.white

  static var selectableStyles: [NotePaperStyle] {
    allCases.filter { $0 != .automatic }
  }

  var id: String { rawValue }

  var name: String {
    switch self {
    case .automatic: "Use Default"
    case .white: "White"
    case .cream: "Cream"
    case .black: "Black"
    case .softBlue: "Soft Blue"
    }
  }

  var isDark: Bool { self == .black }

  func resolved(defaultRawValue: String) -> NotePaperStyle {
    guard self == .automatic else { return self }
    let fallback = NotePaperStyle(rawValue: defaultRawValue) ?? Self.defaultStyle
    return fallback == .automatic ? Self.defaultStyle : fallback
  }
}

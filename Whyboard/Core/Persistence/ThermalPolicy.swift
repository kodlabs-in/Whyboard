import Foundation

nonisolated enum ThermalPolicy {
  static var allowsSpeculativeWork: Bool {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal, .fair:
      true
    case .serious, .critical:
      false
    @unknown default:
      false
    }
  }
}

import Foundation

@MainActor
final class PendingSaveRegistry {
  typealias Flusher = @MainActor () async -> Bool

  private var flushers: [UUID: Flusher] = [:]

  func register(noteID: UUID, flusher: @escaping Flusher) {
    flushers[noteID] = flusher
  }

  func unregister(noteID: UUID) {
    flushers[noteID] = nil
  }

  func flush(noteID: UUID) async -> Bool {
    guard let flusher = flushers[noteID] else { return true }
    return await flusher()
  }

  func flushAll(noteIDs: [UUID]) async -> Bool {
    for noteID in noteIDs where !(await flush(noteID: noteID)) {
      return false
    }
    return true
  }
}

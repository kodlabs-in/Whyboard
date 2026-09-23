import Foundation

struct PendingSaveRegistration: Hashable, Sendable {
  fileprivate let noteID: UUID
  fileprivate let ownerID: UUID
}

@MainActor
final class PendingSaveRegistry {
  typealias Flusher = @MainActor () async -> Bool

  private var flushers: [UUID: [UUID: Flusher]] = [:]

  @discardableResult
  func register(noteID: UUID, flusher: @escaping Flusher) -> PendingSaveRegistration {
    let registration = PendingSaveRegistration(noteID: noteID, ownerID: UUID())
    flushers[noteID, default: [:]][registration.ownerID] = flusher
    return registration
  }

  func unregister(_ registration: PendingSaveRegistration) {
    flushers[registration.noteID]?[registration.ownerID] = nil
    if flushers[registration.noteID]?.isEmpty == true {
      flushers[registration.noteID] = nil
    }
  }

  func flush(noteID: UUID) async -> Bool {
    guard let owners = flushers[noteID] else { return true }
    var didFlushEveryOwner = true
    for flusher in Array(owners.values) where !(await flusher()) {
      didFlushEveryOwner = false
    }
    return didFlushEveryOwner
  }

  func flushAll(noteIDs: [UUID]) async -> Bool {
    var didFlushEveryNote = true
    for noteID in noteIDs where !(await flush(noteID: noteID)) {
      didFlushEveryNote = false
    }
    return didFlushEveryNote
  }
}

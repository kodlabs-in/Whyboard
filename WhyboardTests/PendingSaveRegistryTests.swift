import Foundation
import Testing

@testable import Whyboard

@MainActor
struct PendingSaveRegistryTests {
  @Test func keepsIndependentOwnersForTheSameNote() async {
    let registry = PendingSaveRegistry()
    let noteID = UUID()
    var firstFlushCount = 0
    var secondFlushCount = 0
    let first = registry.register(noteID: noteID) {
      firstFlushCount += 1
      return true
    }
    _ = registry.register(noteID: noteID) {
      secondFlushCount += 1
      return true
    }

    registry.unregister(first)
    let flushed = await registry.flush(noteID: noteID)

    #expect(flushed)
    #expect(firstFlushCount == 0)
    #expect(secondFlushCount == 1)
  }

  @Test func attemptsEveryOwnerAndNoteBeforeReportingFailure() async {
    let registry = PendingSaveRegistry()
    let firstNoteID = UUID()
    let secondNoteID = UUID()
    var attemptedOwners: [String] = []
    registry.register(noteID: firstNoteID) {
      attemptedOwners.append("first-failure")
      return false
    }
    registry.register(noteID: firstNoteID) {
      attemptedOwners.append("first-success")
      return true
    }
    registry.register(noteID: secondNoteID) {
      attemptedOwners.append("second-success")
      return true
    }

    let flushed = await registry.flushAll(noteIDs: [firstNoteID, secondNoteID])

    #expect(!flushed)
    #expect(Set(attemptedOwners) == ["first-failure", "first-success", "second-success"])
  }
}

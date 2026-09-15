import Foundation
import Testing

@testable import Whyboard

@MainActor
struct PageLifecycleTests {
  @Test func keepsOneLeadingAndTwoTrailingPagesLive() {
    let pageIDs = (0..<10).map { _ in UUID() }

    let live = PageWindow.livePageIDs(
      orderedPageIDs: pageIDs,
      visiblePageIDs: [pageIDs[4]])

    #expect(live == Set(pageIDs[3...6]))
  }

  @Test func clampsTheLiveWindowAtNoteEdges() {
    let pageIDs = (0..<5).map { _ in UUID() }

    let start = PageWindow.livePageIDs(
      orderedPageIDs: pageIDs,
      visiblePageIDs: [pageIDs[0]])
    let end = PageWindow.livePageIDs(
      orderedPageIDs: pageIDs,
      visiblePageIDs: [pageIDs[4]])

    #expect(start == Set(pageIDs[0...2]))
    #expect(end == Set(pageIDs[3...4]))
  }

  @Test func aHundredPageNoteKeepsOnlyTheNearbyWindowLive() {
    let pageIDs = (0..<100).map { _ in UUID() }

    let live = PageWindow.livePageIDs(
      orderedPageIDs: pageIDs,
      visiblePageIDs: [pageIDs[50]])

    #expect(live.count == 4)
    #expect(live == Set(pageIDs[49...52]))
  }

  @Test func noVisiblePageProducesNoLiveCanvas() {
    let pageIDs = (0..<3).map { _ in UUID() }
    #expect(PageWindow.livePageIDs(orderedPageIDs: pageIDs, visiblePageIDs: []).isEmpty)
  }
}

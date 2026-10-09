import Foundation
import Testing

@testable import Shutter

private let start = Date(timeIntervalSinceReferenceDate: 0)

/// Feeds one reading every 2 seconds from `from` (seconds) and returns
/// each zone the tracker reported, with the time it did.
private func feed(
    _ tracker: inout AmbientTracker, lux: Double, from: TimeInterval, to: TimeInterval
) -> [(TimeInterval, AmbientTracker.Zone)] {
    var reported: [(TimeInterval, AmbientTracker.Zone)] = []
    for t in stride(from: from, through: to, by: 2) {
        if let zone = tracker.feed(lux: lux, at: start + t) {
            reported.append((t, zone))
        }
    }
    return reported
}

@Test func lightBetweenTheThresholdsIsNeither() {
    #expect(AmbientTracker.zone(lux: 9, darkBelow: 10) == .dark)
    #expect(AmbientTracker.zone(lux: 10, darkBelow: 10) == nil)
    #expect(AmbientTracker.zone(lux: 40, darkBelow: 10) == nil)
    #expect(AmbientTracker.zone(lux: 41, darkBelow: 10) == .light)
}

@Test func firstDecisionComesQuickly() {
    var tracker = AmbientTracker(darkBelow: 10)
    let reported = feed(&tracker, lux: 3, from: 0, to: 20)
    #expect(reported.map(\.0) == [6] && reported.map(\.1) == [.dark])
}

@Test func laterChangesWaitForTheLightToStay() {
    var tracker = AmbientTracker(darkBelow: 10)
    _ = feed(&tracker, lux: 3, from: 0, to: 10)
    let reported = feed(&tracker, lux: 200, from: 12, to: 60)
    #expect(reported.map(\.0) == [22] && reported.map(\.1) == [.light])
}

@Test func aPassingShadowChangesNothing() {
    var tracker = AmbientTracker(darkBelow: 10)
    _ = feed(&tracker, lux: 200, from: 0, to: 10)
    // Dark for 6 seconds, then bright again: never long enough.
    #expect(feed(&tracker, lux: 2, from: 12, to: 18).isEmpty)
    #expect(feed(&tracker, lux: 200, from: 20, to: 26).isEmpty)
    #expect(feed(&tracker, lux: 2, from: 28, to: 34).isEmpty)
}

@Test func dimLightKeepsWhateverWasSettled() {
    var tracker = AmbientTracker(darkBelow: 10)
    _ = feed(&tracker, lux: 3, from: 0, to: 10)
    // 25 lux is brighter than the dark threshold but not light yet.
    #expect(feed(&tracker, lux: 25, from: 12, to: 600).isEmpty)
    #expect(tracker.settled == .dark)
}

@Test func aSettledZoneIsReportedOnce() {
    // So a switch made by hand afterwards stands.
    var tracker = AmbientTracker(darkBelow: 10)
    #expect(feed(&tracker, lux: 3, from: 0, to: 600).count == 1)
}

@Test func aGapStartsTheCountOver() {
    var tracker = AmbientTracker(darkBelow: 10)
    _ = feed(&tracker, lux: 200, from: 0, to: 10)
    _ = feed(&tracker, lux: 2, from: 12, to: 18)
    // The Mac slept: the dark before the gap doesn't count toward after it.
    let reported = feed(&tracker, lux: 2, from: 100, to: 140)
    #expect(reported.map(\.0) == [110])
}

@Test func anInterruptionStartsTheCountOverButKeepsTheZone() {
    var tracker = AmbientTracker(darkBelow: 10)
    _ = feed(&tracker, lux: 200, from: 0, to: 10)
    _ = feed(&tracker, lux: 2, from: 12, to: 18)
    tracker.interrupt()
    #expect(tracker.settled == .light)
    let reported = feed(&tracker, lux: 2, from: 32, to: 80)
    #expect(reported.map(\.0) == [42])
}

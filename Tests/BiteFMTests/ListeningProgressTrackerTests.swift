import XCTest
@testable import BiteFMCore

final class ListeningProgressTrackerTests: XCTestCase {
    func testFiveMinutesOfContinuousPlaybackAccumulatesFiveMinutes() {
        var tracker = ListeningProgressTracker()

        for second in 0...300 {
            tracker.observe(
                position: Double(second),
                wallTime: Double(second),
                isPlaying: true
            )
        }

        XCTAssertEqual(tracker.accumulatedSeconds, 300, accuracy: 0.001)
    }

    func testPausedTimeDoesNotAccumulate() {
        var tracker = ListeningProgressTracker()

        tracker.observe(position: 0, wallTime: 0, isPlaying: true)
        tracker.observe(position: 10, wallTime: 10, isPlaying: false)
        tracker.observe(position: 11, wallTime: 11, isPlaying: true)

        XCTAssertEqual(tracker.accumulatedSeconds, 1, accuracy: 0.001)
    }

    func testSeekDoesNotAccumulateSkippedTime() {
        var tracker = ListeningProgressTracker()

        tracker.observe(position: 0, wallTime: 0, isPlaying: true)
        tracker.observe(position: 1, wallTime: 1, isPlaying: true)
        tracker.observe(position: 120, wallTime: 2, isPlaying: true)
        tracker.observe(position: 121, wallTime: 3, isPlaying: true)

        XCTAssertEqual(tracker.accumulatedSeconds, 2, accuracy: 0.001)
    }
}

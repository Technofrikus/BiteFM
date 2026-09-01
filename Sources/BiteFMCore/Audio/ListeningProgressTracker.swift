import Foundation

/// Tracks actual archive listening time while rejecting seeks and long callback gaps.
struct ListeningProgressTracker {
    private(set) var accumulatedSeconds: Double = 0
    private var lastObservedPosition: Double?
    private var lastObservedWallTime: TimeInterval?

    mutating func observe(position: Double, wallTime: TimeInterval, isPlaying: Bool) {
        guard let lastPosition = lastObservedPosition,
              let lastWallTime = lastObservedWallTime else {
            lastObservedPosition = position
            lastObservedWallTime = wallTime
            return
        }

        if isPlaying {
            let deltaPosition = position - lastPosition
            let deltaWall = wallTime - lastWallTime
            let looksLikeSeek = deltaPosition < 0 || deltaPosition > 6 || deltaWall < 0 || deltaWall > 10
            if !looksLikeSeek {
                accumulatedSeconds += min(max(0, deltaPosition), max(0, deltaWall))
            }
        }

        lastObservedPosition = position
        lastObservedWallTime = wallTime
    }
}

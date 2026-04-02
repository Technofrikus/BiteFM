import Foundation
#if os(iOS)
import Network
#endif

/// One-shot „is there a usable network path?“ for gating playback/downloads and launch routing.
/// Keep the symbol visible on all platforms to avoid `Cannot find ... in scope` issues.
public enum NetworkPathProbe {
    public static func isPathSatisfied(timeoutSeconds: TimeInterval = 3) async -> Bool {
#if os(iOS)
        return await withCheckedContinuation { continuation in
            let state = PathResumeBox(continuation)
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "fm.byte.bitefm.pathprobe")
            monitor.pathUpdateHandler = { path in
                let ok = path.status == .satisfied
                monitor.cancel()
                state.resumeOnce(ok)
            }
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeoutSeconds) {
                monitor.cancel()
                state.resumeOnce(false)
            }
        }
#else
        // For non-iOS targets we don't gate network-sensitive UI flows.
        return true
#endif
    }
}

#if os(iOS)
private final class PathResumeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private let continuation: CheckedContinuation<Bool, Never>

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resumeOnce(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        continuation.resume(returning: value)
    }
}
#endif

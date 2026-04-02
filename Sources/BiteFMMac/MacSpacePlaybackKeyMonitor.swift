#if os(macOS)
import AppKit
import BiteFMCore

/// `Text` mit `.textSelection` verwendet eine nicht editierbare `NSTextView`, die die Leertaste für Scrollen nutzt.
/// Damit die globale Play/Pause-Taste weiter funktioniert, wird Space in diesem Fall abgefangen.
enum MacSpacePlaybackKeyMonitor {
    private static var monitor: Any?
    
    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 49 else { return event }
            guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return event }
            
            guard let responder = NSApp.keyWindow?.firstResponder else { return event }
            
            guard let textView = responder as? NSTextView, !textView.isEditable else {
                return event
            }
            
            guard Thread.isMainThread else { return event }
            
            var outcome: NSEvent? = event
            MainActor.assumeIsolated {
                let canToggle = AudioPlayerManager.shared.currentItem != nil || AudioPlayerManager.shared.isLive
                guard canToggle else { return }
                AudioPlayerManager.shared.togglePlayPause()
                outcome = nil
            }
            return outcome
        }
    }
}
#endif

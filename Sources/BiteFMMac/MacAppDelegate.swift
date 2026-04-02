//
//  MacAppDelegate.swift
//  BiteFM
//
//  Dock-Kontextmenü für Wiedergabe (Rechtsklick auf das Dock-Symbol).
//

#if os(macOS)
import AppKit
import BiteFMCore

/// Dock-Kontextmenü (Rechtsklick auf das Dock-Symbol): Wiedergabe steuern.
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        MacSpacePlaybackKeyMonitor.install()
        MacPlaybackGlobalHotkey.install()
    }
    
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        
        let playPauseTitle: String
        let canPlayPause: Bool
        let canSkip: Bool
        
        if Thread.isMainThread {
            (playPauseTitle, canPlayPause, canSkip) = Self.playbackMenuState()
        } else {
            (playPauseTitle, canPlayPause, canSkip) = DispatchQueue.main.sync {
                Self.playbackMenuState()
            }
        }
        
        let playPause = NSMenuItem(title: playPauseTitle, action: #selector(dockPlayPause(_:)), keyEquivalent: "")
        playPause.target = self
        playPause.isEnabled = canPlayPause
        menu.addItem(playPause)
        
        let next = NSMenuItem(title: "Nächster Titel", action: #selector(dockSkipNext(_:)), keyEquivalent: "")
        next.target = self
        next.isEnabled = canSkip
        menu.addItem(next)
        
        let prev = NSMenuItem(title: "Vorheriger Titel", action: #selector(dockSkipPrevious(_:)), keyEquivalent: "")
        prev.target = self
        prev.isEnabled = canSkip
        menu.addItem(prev)
        
        return menu
    }
    
    private static func playbackMenuState() -> (title: String, canPlayPause: Bool, canSkip: Bool) {
        MainActor.assumeIsolated {
            let m = AudioPlayerManager.shared
            let title = m.isPlaying ? "Pause" : "Abspielen"
            let canPlayPause = m.currentItem != nil || m.isLive
            let canSkip = m.currentPlaylist != nil
            return (title, canPlayPause, canSkip)
        }
    }
    
    @objc private func dockPlayPause(_ sender: Any?) {
        Task { @MainActor in
            let m = AudioPlayerManager.shared
            guard m.currentItem != nil || m.isLive else { return }
            m.togglePlayPause()
        }
    }
    
    @objc private func dockSkipNext(_ sender: Any?) {
        Task { @MainActor in
            AudioPlayerManager.shared.skipNext()
        }
    }
    
    @objc private func dockSkipPrevious(_ sender: Any?) {
        Task { @MainActor in
            AudioPlayerManager.shared.skipPrevious()
        }
    }
}
#endif

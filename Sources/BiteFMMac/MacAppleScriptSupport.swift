//
//  MacAppleScriptSupport.swift
//  BiteFM
//
//  Cocoa Scripting: player state and transport commands (Music-compatible terminology).
//

#if os(macOS)
import AppKit
import BiteFMCore

enum MacAppleScriptPlayerState {
    static let stopped: UInt32 = fourCharCode("kPSS")
    static let playing: UInt32 = fourCharCode("kPSP")
    static let paused: UInt32 = fourCharCode("kPSp")

    private static func fourCharCode(_ string: String) -> UInt32 {
        var result: UInt32 = 0
        for (index, char) in string.utf8.prefix(4).enumerated() {
            result |= UInt32(char) << (8 * (3 - index))
        }
        return result
    }
}

func macAppleScriptPlayerState(isPlaying: Bool, hasContent: Bool) -> UInt32 {
    if isPlaying {
        return MacAppleScriptPlayerState.playing
    }
    if hasContent {
        return MacAppleScriptPlayerState.paused
    }
    return MacAppleScriptPlayerState.stopped
}

func macAppleScriptCurrentPlayerState() -> UInt32 {
    if Thread.isMainThread {
        return MainActor.assumeIsolated {
            let manager = AudioPlayerManager.shared
            return macAppleScriptPlayerState(
                isPlaying: manager.isPlaying,
                hasContent: manager.currentItem != nil || manager.isLive
            )
        }
    }
    return DispatchQueue.main.sync {
        MainActor.assumeIsolated {
            let manager = AudioPlayerManager.shared
            return macAppleScriptPlayerState(
                isPlaying: manager.isPlaying,
                hasContent: manager.currentItem != nil || manager.isLive
            )
        }
    }
}

private func runOnMainActor(_ block: @MainActor () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated(block)
    } else {
        DispatchQueue.main.sync {
            MainActor.assumeIsolated(block)
        }
    }
}

@objc(BiteFMPlayScriptCommand)
final class BiteFMPlayScriptCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        runOnMainActor {
            let manager = AudioPlayerManager.shared
            guard manager.currentItem != nil || manager.isLive else { return }
            if !manager.isPlaying {
                manager.togglePlayPause()
            }
        }
        return nil
    }
}

@objc(BiteFMPauseScriptCommand)
final class BiteFMPauseScriptCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        runOnMainActor {
            let manager = AudioPlayerManager.shared
            if manager.isPlaying {
                manager.togglePlayPause()
            }
        }
        return nil
    }
}

@objc(BiteFMPlayPauseScriptCommand)
final class BiteFMPlayPauseScriptCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        runOnMainActor {
            let manager = AudioPlayerManager.shared
            guard manager.currentItem != nil || manager.isLive else { return }
            manager.togglePlayPause()
        }
        return nil
    }
}

@objc(BiteFMStopScriptCommand)
final class BiteFMStopScriptCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        runOnMainActor {
            let manager = AudioPlayerManager.shared
            if manager.isPlaying {
                manager.togglePlayPause()
            }
        }
        return nil
    }
}
#endif

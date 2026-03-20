//
//  MacPlaybackGlobalHotkey.swift
//  BiteFM
//
//  Globale Tastenkombination ⌥⌘P für Play/Pause (Carbon RegisterEventHotKey).
//

#if os(macOS)
import AppKit
import Carbon

private let kBiteFMPlaybackHotKeyID: UInt32 = 1
/// Vier-Zeichen-Code `BTFM` (Big-Endian).
private let kBiteFMHotKeySignature: OSType = 0x4254_464D

/// Globale Tastenkombination ⌥⌘P zum Pausieren/Abspielen (zusätzlich zu den Medientasten).
private func biteFMHotKeyEventHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    guard hotKeyID.id == kBiteFMPlaybackHotKeyID,
          hotKeyID.signature == kBiteFMHotKeySignature else {
        return OSStatus(eventNotHandledErr)
    }
    
    DispatchQueue.main.async {
        Task { @MainActor in
            let m = AudioPlayerManager.shared
            guard m.currentItem != nil || m.isLive else { return }
            m.togglePlayPause()
        }
    }
    return noErr
}

enum MacPlaybackGlobalHotkey {
    private static var hotKeyRef: EventHotKeyRef?
    private static var eventHandlerRef: EventHandlerRef?
    
    static func install() {
        guard hotKeyRef == nil else { return }
        
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let installHandlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            biteFMHotKeyEventHandler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
        guard installHandlerStatus == noErr else { return }
        
        let hotKeyID = EventHotKeyID(signature: kBiteFMHotKeySignature, id: kBiteFMPlaybackHotKeyID)
        let regStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_P),
            UInt32(cmdKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard regStatus == noErr else { return }
    }
}
#endif

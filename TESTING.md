# Test matrix (BiteFM)

## Automated

- **macOS**: `swift test` (SPM) — shared logic in `BiteFMCore` (models, favorites, archive helpers).
- **Xcode**: Run **BiteFM** scheme → **BiteFMTests** (same sources, macOS host).

## Manual UI checks

Repeat on **Mac (regular width)** and **iPhone (compact)**; iPad can use either size class depending on multitasking.

| Area | Compact (iPhone) | Regular (Mac / iPad wide) |
|------|------------------|-----------------------------|
| Root navigation | `TabView`: Live, Neu, Archiv, Favoriten hub | `NavigationSplitView` sidebar + detail |
| Inspector / details | Sheet over list | macOS inspector column |
| Live | Smaller artwork; full-width stream button | Large artwork; fixed-width button |
| Archiv | No A–Z side strip; searchable list | A–Z index strip + scroll |
| Favoriten: Ausgaben | Sort via toolbar **Menu** | Segmented sort in toolbar |
| Player bar | Stacked compact layout | Single-row layout |
| Audio | Background: **audio** in `Info-iOS.plist`; lock screen / interruption | N/A |

## Audio / lifecycle (iOS)

- Start Live or Archiv playback, lock device: audio continues (with background mode).
- Incoming call / Siri: playback pauses; after end, resume if system reports `shouldResume`.

# BiteFM Agent Instructions

BiteFM is a native radio client for ByteFM, built for macOS and iOS using SwiftUI, SwiftData, and AVFoundation.

## Build & Test Commands
- **Generate Xcode Project**: `xcodegen generate`
- **Build (SPM)**: `swift build`
- **Run Tests (SPM)**: `swift test`
- **Build Specific Target**: `swift build --product [BiteFMCore|BiteFMMac]`
- **Bump Patch Version**: `swift Tools/bump-version.swift patch`

### Agent build notes (non-interactive terminal)
- **Set the terminal `cd` parameter to the absolute project path** (`/Users/tf/Nextcloud/gitfolder/BiteFM`). This is the working way to run commands — the terminal tool requires the directory to be passed via its `cd` parameter, not via a `cd` inside the command string. Commands run this way (e.g. `swift build`) succeed.
- **Prefer `swift build` / `swift test`** (SPM) over `xcodebuild` for agent-driven compilation — it is non-interactive and avoids signing/license prompts.
- **`xcodebuild` can hang** waiting on stdin (unaccepted Xcode license, signing identity, keychain unlock). If you must use it, accept the license once yourself (`sudo xcodebuild -license accept`) and pass non-interactive flags (`-quiet`, `-allowProvisioningUpdates`); never rely on stdin. A hang is the prompt, not a missing toolchain.
- **SPM builds run on the host platform only.** `swift build` on macOS compiles the macOS path and **excludes `#if os(iOS)` code**. Changes inside iOS-only blocks (e.g. `AVAudioSession` setup in `AudioPlayerManager`) are NOT validated by `swift build` — verify those with an iOS build (`xcodebuild -scheme BiteFMiOS -sdk iphonesimulator build`, or build the BiteFMiOS scheme in Xcode).

## Versioning
- **Build Number**: Automated via Git commit count in `pre-commit` hook.
- **Marketing Version**: Manual in `project.yml` for Major/Minor, or via `swift Tools/bump-version.swift patch` for Patch updates.
- **Source of Truth**: `project.yml`. Never change version in Xcode directly.

## Key Conventions
- **Architecture**: Modular design with `BiteFMCore` (logic, models, views) and platform-specific targets (`BiteFMMac`, `BiteFMiOS`).
- **Module layout** (`Sources/BiteFMCore/`):
  - `Networking/` — `APIClient` (networking facade), `BroadcastDetailLRUCache`, `KeychainHelper`, `LogManager`, `NetworkPathProbe`.
  - `Audio/` — `AudioPlayerManager` (`AVPlayer` wrapper), `ActivePlaybackStore` (narrow "which row is active" snapshot), `PlaybackProgressStore`.
  - `AppState/` — `AppRestorationState`, `AppRestorationStore`, and `FavoritePlayedStore` (narrow favorite/played snapshot for list rows).
  - `Models/` — SwiftData models (`StoredArchiveItem`, `StoredShow`, `StoredFavoriteBroadcast`, `StoredListeningHistoryEntry`, …) and API response models (`Show`, `ArchiveItem`, `LiveMetadata`, `FavoriteBroadcast`, `FavoriteStateLogic`).
  - `Views/` — SwiftUI views. Shared list rows go through `BroadcastRow` + `makeBroadcastRow`, which take a `FavoritePlayedState` snapshot rather than observing the whole `APIClient`.
  - `Downloads/` — `IOSDownloadManager` (iOS only) + models.
  - `Utils/` — pure helpers (`ArchivAudioURL`, `ArchiveSectionHelpers`).
  - `BiteFMBootstrap.swift` — SwiftData container + service wiring (`configureServices`).
- **UI**: Pure SwiftUI with adaptive layouts for Mac and iPhone.
- **Data**: `SwiftData` for persistent storage of archive items and playback history.
- **Audio**: `AVFoundation` (`AVPlayer`) for streaming and archive playback.
- **System Integration**: `MediaPlayer` framework for Now Playing and media keys.
- **API**: Custom ByteFM API integration (see `Sources/BiteFMCore/BiteFMBootstrap.swift` and models). Domain vocabulary lives in `CONTEXT.md`.

## macOS sandbox playback console noise (last verified 2026-05-29)

When playing archive audio in the **sandboxed** Mac app (`BiteFMMac.entitlements`: app-sandbox + network.client only), Xcode may log:

`PRECONDITION FAILURE: Process is sandboxed but 'com.apple.security.exception.mach-lookup.global-name' doesn't contain 'com.apple.audioanalyticsd'.`

**Expected behavior:** Playback works; this is AVFoundation/CoreAudio trying to reach Apple’s private `audioanalyticsd` daemon, not app code. Also common with newer Xcode/macOS SDKs for sandboxed apps that use `AVPlayer`.

**Do not** add `com.apple.audioanalyticsd` to `com.apple.security.exception.mach-lookup.global-name` by default — fragile/private Mach service, App Store / notarization risk. Treat as console noise unless playback actually fails.

Other frequent, usually harmless logs during playback: `nw_connection` / Happy Eyeballs, `FigFilePlayer err=-12864`, `HALC_ProxyIOContext … overload` (debug/system load). Use structured app logs (`Playback failure` with URL and `AVPlayerItem.error` in `AudioPlayerManager`) for real failures, not these system lines.

Archive URLs: use `ArchivAudioURL.make(from:)` in `Sources/BiteFMCore/Utils/ArchivAudioURL.swift` (player + downloads), not raw string concatenation to `https://archiv.bytefm.com/`.

## Commit Attribution
AI commits MUST include:
```
Co-Authored-By: Gemini 3.1 Flash <noreply@moinboards.com>
```

## File-Scoped Commands
| Task | Command |
|------|---------|
| Build File | `swift build --target [TargetName]` |
| Test File | `swift test --filter [TestClassName]` |

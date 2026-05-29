# BiteFM Agent Instructions

BiteFM is a native radio client for ByteFM, built for macOS and iOS using SwiftUI, SwiftData, and AVFoundation.

## Build & Test Commands
- **Generate Xcode Project**: `xcodegen generate`
- **Build (SPM)**: `swift build`
- **Run Tests (SPM)**: `swift test`
- **Build Specific Target**: `swift build --product [BiteFMCore|BiteFMMac]`
- **Bump Patch Version**: `swift Tools/bump-version.swift patch`

## Versioning
- **Build Number**: Automated via Git commit count in `pre-commit` hook.
- **Marketing Version**: Manual in `project.yml` for Major/Minor, or via `swift Tools/bump-version.swift patch` for Patch updates.
- **Source of Truth**: `project.yml`. Never change version in Xcode directly.

## Key Conventions
- **Architecture**: Modular design with `BiteFMCore` (logic, models, views) and platform-specific targets (`BiteFMMac`, `BiteFMiOS`).
- **UI**: Pure SwiftUI with adaptive layouts for Mac and iPhone.
- **Data**: `SwiftData` for persistent storage of archive items and playback history.
- **Audio**: `AVFoundation` (`AVPlayer`) for streaming and archive playback.
- **System Integration**: `MediaPlayer` framework for Now Playing and media keys.
- **API**: Custom ByteFM API integration (see `Sources/BiteFMCore/BiteFMBootstrap.swift` and models).

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

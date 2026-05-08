# BiteFM Agent Instructions

BiteFM is a native radio client for ByteFM, built for macOS and iOS using SwiftUI, SwiftData, and AVFoundation.

## Build & Test Commands
- **Generate Xcode Project**: `xcodegen generate`
- **Build (SPM)**: `swift build`
- **Run Tests (SPM)**: `swift test`
- **Build Specific Target**: `swift build --product [BiteFMCore|BiteFMMac]`

## Key Conventions
- **Architecture**: Modular design with `BiteFMCore` (logic, models, views) and platform-specific targets (`BiteFMMac`, `BiteFMiOS`).
- **UI**: Pure SwiftUI with adaptive layouts for Mac and iPhone.
- **Data**: `SwiftData` for persistent storage of archive items and playback history.
- **Audio**: `AVFoundation` (`AVPlayer`) for streaming and archive playback.
- **System Integration**: `MediaPlayer` framework for Now Playing and media keys.
- **API**: Custom ByteFM API integration (see `Sources/BiteFMCore/BiteFMBootstrap.swift` and models).

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

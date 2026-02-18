# CLAUDE.md — AI Sailing Coach (iOS)

## Project Overview

Tactical sailing instrument and AI coaching app for regatta sailors. Built with SwiftUI for iOS 17+.

- **Bundle ID**: `app.spatialsail.AISailingCoach`
- **Platform**: iOS 17.0+
- **Language**: Swift 5.0
- **UI Framework**: SwiftUI (dark mode only)

## Build & Run

**Requirements**: macOS + Xcode 15.0+ (cannot build on Linux)

```bash
open AISailingCoach.xcodeproj
# Then build and run in Xcode (Cmd+R) on a simulator or device
```

No external package managers are used. No `pod install`, `swift package resolve`, or similar commands needed.

## Architecture

MVVM pattern with `@MainActor` view model and Combine for reactive data flow.

```
AISailingCoach/
├── App/
│   └── AISailingCoachApp.swift      # @main entry point, injects SailingViewModel
├── Models/
│   ├── SailingData.swift            # Core telemetry struct (COG, speed, wind, performance)
│   ├── SignalKMessage.swift         # Signal K delta message decoding
│   └── CoachRecommendations.swift   # Visual coach output model
├── ViewModels/
│   └── SailingViewModel.swift       # @MainActor ObservableObject — all app state
├── Services/
│   ├── SignalKSimulator.swift       # Generates simulated sailing data at configurable rate
│   ├── GeminiCoachService.swift     # Voice AI coach via Gemini Live API (WebSocket)
│   ├── GeminiLiveClient.swift       # Low-level Gemini Live WebSocket client
│   ├── Gemini3VisualCoachService.swift # Visual coach via Gemini 3 Flash REST/SSE
│   └── SpeechService.swift          # Speech recognition (STT) and TTS
├── Views/
│   ├── ContentView.swift            # Root layout
│   ├── Instruments/                 # CompassRoseView, DataBoxesView, PerformanceGaugeView,
│   │                                #   CoachInstructionPanesView
│   ├── Coach/                       # CoachButtonView (push-to-talk)
│   ├── Settings/                    # SettingsView
│   └── Components/                  # ColorExtensions
└── Configuration/
    └── Secrets.swift                # APIConfiguration enum — API keys & feature flags
```

## Key Data Flow

1. `SignalKSimulator` (or real Signal K WebSocket) → publishes `SailingData`
2. `SailingViewModel` receives updates, exposes `@Published` properties
3. SwiftUI views observe via `.environmentObject(viewModel)`
4. `GeminiCoachService` sends sailing context to Gemini Live for voice coaching
5. `Gemini3VisualCoachService` polls every ~10 seconds for visual `CoachRecommendations`

## API Configuration

API keys are **not** hardcoded. `APIConfiguration` in `Secrets.swift` resolves keys:

1. `GEMINI_API_KEY` environment variable (CI/CD)
2. `UserDefaults` key `"GeminiAPIKey"` (set in app Settings UI)

Get a Gemini API key at: https://aistudio.google.com/apikey

## AI Services

### Voice Coach (Gemini Live API)
- Real-time bidirectional audio via WebSocket
- Push-to-talk interface
- Receives full `SailingData` context with each query

### Visual Coach (Gemini 3 Flash)
- REST + SSE streaming (`streamGenerateContent`)
- Returns structured JSON: `recommendedHeadsail`, `steeringRecommendation`, `sailTrimRecommendation`
- Updates 4 instruction panes: Performance, Headsail, Steering, Sail Trim
- Configurable via `isVisualCoachActive` (persisted in UserDefaults)

## Signal K Integration

Standard Signal K delta format over WebSocket. Units are **radians** and **m/s** in the protocol; the app converts to degrees and knots for display.

Key paths used:
- `navigation.courseOverGroundTrue`
- `navigation.speedOverGround`
- `environment.wind.speedTrue`
- `environment.wind.angleTrueWater`

Default URL: `ws://localhost:3000/signalk/v1/stream`

## Simulation Scenarios

Available via `SimulationScenario` enum in `SignalKSimulator`:
`upwind`, `downwind`, `reaching`, `raceStart`, `windShift`, `gust`

Switch scenarios in Settings UI. Simulator runs at configurable update rate (UserDefaults key `"UpdateRate"`).

## Feature Flags

Defined in `APIConfiguration` (`Secrets.swift`):

| Flag | Default | Purpose |
|------|---------|---------|
| `enableAppleFoundationModels` | `false` | On-device AI (future) |
| `enableTacticalFeatures` | `false` | Advanced tactics (future) |
| `enableRaceTimer` | `true` | Race timer UI |

## Design System (Spatial Sail)

| Color | Hex | Usage |
|-------|-----|-------|
| Spatial Yellow | `#FDB714` | Primary accent, high performance |
| Spatial Turquoise | `#A5D8DD` | True wind, secondary accent |
| Performance Red | `#ef4444` | Low performance, port layline |
| Layline Green | `#10b981` | Starboard layline |

See `ColorExtensions.swift` for Color assets.

## Permissions Required

- **Microphone** — Push-to-talk voice coach
- **Speech Recognition** — STT for voice queries

## Important Notes

- The app enforces `.preferredColorScheme(.dark)` — all UI is dark mode only
- `SailingViewModel` is `@MainActor` — all UI updates happen on main thread
- No unit tests exist in the current codebase
- No SwiftLint or other linters are configured
- Building requires macOS; this repo cannot be compiled in Linux/web environments

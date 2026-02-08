# AI Sailing Coach - iOS App

A tactical sailing instrument and AI coaching app for regatta sailors. Built with SwiftUI for iOS 17+.

## Features

### 📊 Real-Time Instruments
- **Compass Rose**: Rotating compass card with COG display, wind angle indicators (TWA/AWA), and laylines
- **Speed Display**: Boat speed and target speed from polar data

### 🎙️ AI Sailing Coach (Gemini Live API)
- Push-to-talk voice interface for hands-free coaching
- Context-aware advice based on current sailing conditions
- Real-time tactical suggestions for performance optimization

### ⛵ Signal K Integration
- Simulated Signal K server for development/testing
- Standard Signal K delta message format
- Ready for real boat connection via WebSocket

## Getting Started

### Prerequisites
- macOS with Xcode 15.0+
- iOS 17.0+ device or simulator
- Gemini API key (for AI coaching features)

### Setup

1. **Open the project in Xcode**
   ```bash
   open AISailingCoach.xcodeproj
   ```

2. **Configure your Gemini API Key**
   - Launch the app
   - Tap the ⚙️ settings button (top-right)
   - Enter your Gemini API key
   - Get a key at: https://aistudio.google.com/apikey

3. **Build and run** on your device or simulator

### Simulator Mode

The app includes a Signal K simulator that generates realistic sailing data. You can switch between scenarios in Settings:

| Scenario | Description |
|----------|-------------|
| Upwind | Close-hauled sailing with good VMG |
| Downwind | Running/broad reach conditions |
| Reaching | Beam reach at maximum speed |
| Race Start | Pre-start maneuvering sequence |
| Wind Shift | Progressive wind shift scenario |
| Gust | Gusty conditions with lulls |

## Architecture

```
AISailingCoach/
├── App/                    # App entry point
├── Models/                 # Data models
│   ├── SailingData.swift   # Core telemetry model
│   └── SignalKMessage.swift # Signal K protocol
├── Views/
│   ├── ContentView.swift   # Main layout
│   ├── Instruments/        # Compass, gauges, displays
│   ├── Coach/              # Push-to-talk UI
│   └── Settings/           # Configuration
├── ViewModels/
│   └── SailingViewModel.swift # Observable state
├── Services/
│   ├── SignalKSimulator.swift # Data simulation
│   ├── GeminiCoachService.swift # AI integration
│   └── SpeechService.swift # Voice I/O
└── Configuration/          # API keys, feature flags
```

## Signal K Data Format

The app uses standard Signal K paths:

```json
{
  "context": "vessels.self",
  "updates": [{
    "values": [
      {"path": "navigation.courseOverGroundTrue", "value": 0.785},
      {"path": "navigation.speedOverGround", "value": 3.5},
      {"path": "environment.wind.speedTrue", "value": 6.4},
      {"path": "environment.wind.angleTrueWater", "value": 0.733}
    ]
  }]
}
```

Note: Signal K uses radians and m/s; the app converts to degrees and knots for display.

## AI Coach Usage

1. **Press and hold** the microphone button at the bottom
2. **Speak your question** while holding (e.g., "How can I point higher?")
3. **Release** to send your query
4. **Listen** to the AI coach's response

The coach receives your current sailing data with each query, providing context-aware advice.

### Example Queries
- "How's my performance?"
- "Should I tack now?"
- "What's my VMG?"
- "Help me find the groove"
- "The wind is shifting, what should I do?"

## Color Scheme

Based on the Spatial Sail design system:

| Color | Hex | Usage |
|-------|-----|-------|
| Spatial Yellow | `#FDB714` | Primary accent, high performance |
| Spatial Turquoise | `#A5D8DD` | True wind, secondary accent |
| Performance Red | `#ef4444` | Low performance, port layline |
| Layline Green | `#10b981` | Starboard layline |

## Future Roadmap

- [ ] Apple Foundation Models integration (on-device AI)
- [ ] Apple Watch companion app
- [ ] iPad split-view layout
- [ ] Race timer and start sequence
- [ ] Tactical overlay with competitors
- [ ] Performance history charts
- [ ] Real Signal K server discovery (mDNS)
- [ ] Vision Pro AR support

## Requirements

- **iOS**: 17.0+
- **Xcode**: 15.0+
- **Swift**: 5.9+

## Permissions

The app requests the following permissions:
- **Microphone**: Voice commands for AI coach
- **Speech Recognition**: Converting speech to text
- **Location** (future): GPS-based speed and course
- **Bluetooth** (future): External wind sensors
- **Local Network** (future): Signal K server connection

## License

Part of the Spatial Sail project. See LICENSE for details.

## Credits

- **Design**: Based on Figma mockups
- **AI**: Powered by Google Gemini Live API
- **Data Protocol**: Signal K open marine data standard

---

**Built with ⛵ by the Spatial Sail team**

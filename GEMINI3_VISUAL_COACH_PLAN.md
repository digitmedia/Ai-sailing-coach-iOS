# Gemini 3 Visual Coach Implementation Plan

## Overview

Implement a second AI sailing coach that provides **visual instructions** through the 4 UI panes (Performance, Headsail, Steering, Sail Trim) using the **Gemini 3 Flash** API.

---

## 1. Model Selection: Gemini 3 Flash

### Why Gemini 3 Flash?
- **Low latency**: Designed for high-frequency workflows with Flash-level speed
- **Pro-grade intelligence**: 78% on SWE-bench, 90.4% on GPQA Diamond
- **Cost effective**: $0.50/1M input tokens (4x cheaper than 2.5 Pro)
- **Hackathon requirement**: Uses Gemini 3 series

### Model Configuration
```
Model ID: gemini-3-flash-preview
Thinking Level: "minimal" or "low" (for lowest latency)
```

The `thinking_level: "minimal"` setting minimizes internal reasoning, best for:
- Simple instruction following
- High-throughput applications
- Our use case: straightforward sailing recommendations

---

## 2. API Connection Method: REST with Streaming

### Recommendation: `streamGenerateContent` REST API (not WebSocket)

**Why REST over WebSocket?**
1. **Simpler implementation** - No need to maintain persistent connection
2. **Adequate for 10-second intervals** - We don't need real-time bidirectional communication
3. **Better error recovery** - Each request is independent
4. **Lower complexity** - No connection state management

### API Endpoint
```
POST https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:streamGenerateContent?alt=sse&key={API_KEY}
```

### Request Format
```json
{
  "contents": [{
    "parts": [{
      "text": "System prompt + sailing data"
    }]
  }],
  "generationConfig": {
    "temperature": 0.3,
    "maxOutputTokens": 200,
    "thinkingConfig": {
      "thinkingLevel": "minimal"
    },
    "responseMimeType": "application/json"
  }
}
```

### Response Format (JSON mode)
```json
{
  "recommendedHeadsail": "genoa",
  "steeringRecommendation": "steady",
  "sailTrimRecommendation": "hold"
}
```

---

## 3. Architecture

### New Files to Create

```
AISailingCoach/
├── Services/
│   └── Gemini3VisualCoachService.swift    # NEW - Gemini 3 API client
├── Models/
│   └── CoachRecommendations.swift         # NEW - Response data model
```

### Files to Modify

```
├── ViewModels/
│   └── SailingViewModel.swift             # Add visual coach integration
├── Views/
│   └── Instruments/
│       └── CoachInstructionPanesView.swift # Connect panes to recommendations
├── Services/
│   └── GeminiCoachService.swift           # Rename timer (avoid conflict)
```

---

## 4. Data Flow

```
┌─────────────────┐     Every 10s      ┌──────────────────────┐
│  SignalK        │ ──────────────────►│  Gemini3Visual       │
│  Simulator      │                    │  CoachService        │
└─────────────────┘                    └──────────────────────┘
        │                                        │
        │ SailingData                            │ REST API
        ▼                                        ▼
┌─────────────────┐                    ┌──────────────────────┐
│  SailingView    │                    │  Gemini 3 Flash      │
│  Model          │◄───────────────────│  API                 │
└─────────────────┘  CoachRecommendations└──────────────────────┘
        │
        │ @Published
        ▼
┌─────────────────────────────────────────────────────────────┐
│  CoachInstructionPanesView                                  │
│  ┌─────────────┐  ┌─────────────┐                          │
│  │ Performance │  │  Headsail   │                          │
│  │   (gauge)   │  │ genoa/code0 │                          │
│  └─────────────┘  └─────────────┘                          │
│  ┌─────────────┐  ┌─────────────┐                          │
│  │  Steering   │  │  Sail Trim  │                          │
│  │ steady/head │  │ hold/sheet  │                          │
│  └─────────────┘  └─────────────┘                          │
└─────────────────────────────────────────────────────────────┘
```

---

## 5. Implementation Details

### 5.1 CoachRecommendations Model

```swift
struct CoachRecommendations: Codable {
    let recommendedHeadsail: HeadsailType
    let steeringRecommendation: SteeringAction
    let sailTrimRecommendation: SailTrimAction
}

// Extend existing enums to be Codable
extension HeadsailType: Codable {}
extension SteeringAction: Codable {}
extension SailTrimAction: Codable {}
```

### 5.2 Gemini3VisualCoachService

```swift
@MainActor
class Gemini3VisualCoachService: ObservableObject {
    @Published var recommendations: CoachRecommendations?
    @Published var isActive: Bool = false
    @Published var lastError: String?

    private var updateTimer: Timer?
    private let updateInterval: TimeInterval = 10.0  // Every 10 seconds
    private var apiKey: String?

    // Callback to get fresh sailing data
    var getSailingData: (() -> SailingData)?

    func start() { /* Start timer */ }
    func stop() { /* Stop timer */ }

    private func fetchRecommendations(for data: SailingData) async {
        // Build prompt with sailing data
        // Call Gemini 3 Flash API
        // Parse JSON response
        // Update @Published recommendations
    }
}
```

### 5.3 System Prompt for Visual Coach

```
You are an expert racing sailing coach analyzing real-time boat telemetry.
Based on the sailing data provided, give concise recommendations for:
1. Headsail selection (genoa, code0, or gennaker)
2. Steering action (steady, headUp, or bearAway)
3. Sail trim action (hold, sheetIn, or ease)

Respond ONLY with a JSON object in this exact format:
{
  "recommendedHeadsail": "genoa" | "code0" | "gennaker",
  "steeringRecommendation": "steady" | "headUp" | "bearAway",
  "sailTrimRecommendation": "hold" | "sheetIn" | "ease"
}

Decision logic:
- Headsail: genoa for TWA < 50°, code0 for 50-90°, gennaker for > 90°
- Steering: Consider performance %, target speed, wind angle optimization
- Sail Trim: Based on boat speed vs target, heel, and wind conditions
```

### 5.4 Sailing Data Sent to API

```swift
let prompt = """
Current sailing data:
- Boat speed: \(data.boatSpeed) kts
- Target speed: \(data.targetSpeed) kts
- Performance: \(data.performance)%
- True wind angle: \(data.trueWindAngle)°
- True wind speed: \(data.trueWindSpeed) kts
- Apparent wind angle: \(data.apparentWindAngle)°
- Course over ground: \(data.courseOverGround)°
- Point of sail: \(data.pointOfSail)

Provide your recommendations:
"""
```

---

## 6. UI Integration

### Update CoachInstructionPanesView

```swift
struct CoachInstructionPanesView: View {
    let performance: Int
    let apparentWindAngle: Double

    // NEW: AI recommendations (optional, falls back to defaults)
    var recommendations: CoachRecommendations?

    // Computed properties with fallback
    private var currentHeadsail: HeadsailType {
        recommendations?.recommendedHeadsail ?? .genoa
    }

    private var currentSteering: SteeringAction {
        recommendations?.steeringRecommendation ?? .steady
    }

    private var currentSailTrim: SailTrimAction {
        recommendations?.sailTrimRecommendation ?? .hold
    }

    var body: some View {
        // ... existing grid layout using computed properties
    }
}
```

### Update SailingViewModel

```swift
class SailingViewModel: ObservableObject {
    // Existing properties...

    // NEW: Visual coach
    private var visualCoachService: Gemini3VisualCoachService?
    @Published var visualCoachRecommendations: CoachRecommendations?
    @Published var isVisualCoachActive: Bool = false

    func setupServices() {
        // ... existing setup

        // Initialize Visual Coach
        visualCoachService = Gemini3VisualCoachService()
        visualCoachService?.getSailingData = { [weak self] in
            self?.sailingData ?? .empty
        }

        // Subscribe to recommendations
        visualCoachService?.$recommendations
            .assign(to: &$visualCoachRecommendations)
    }

    func toggleVisualCoach() {
        if isVisualCoachActive {
            visualCoachService?.stop()
        } else {
            visualCoachService?.start()
        }
        isVisualCoachActive.toggle()
    }
}
```

---

## 7. Error Handling

### API Errors
- Network failure → Keep last recommendations, show subtle error indicator
- Invalid JSON → Use fallback logic (TWA-based headsail, steady, hold)
- Rate limit → Increase interval temporarily

### Fallback Logic (if API unavailable)
```swift
func calculateFallbackRecommendations(from data: SailingData) -> CoachRecommendations {
    // Headsail based on TWA
    let headsail: HeadsailType = {
        if abs(data.trueWindAngle) < 50 { return .genoa }
        if abs(data.trueWindAngle) < 90 { return .code0 }
        return .gennaker
    }()

    // Steering based on performance
    let steering: SteeringAction = data.performance >= 90 ? .steady : .bearAway

    // Trim based on speed
    let trim: SailTrimAction = data.boatSpeed >= data.targetSpeed ? .hold : .sheetIn

    return CoachRecommendations(
        recommendedHeadsail: headsail,
        steeringRecommendation: steering,
        sailTrimRecommendation: trim
    )
}
```

---

## 8. Settings Integration

Add toggle in SettingsView:
- "Visual Coach" ON/OFF switch
- Uses same Gemini API key as voice coach
- Independent from voice coach (can run both or either)

---

## 9. Implementation Order

### Phase 1: Core Service (Day 1)
1. Create `CoachRecommendations.swift` model
2. Create `Gemini3VisualCoachService.swift` with REST API client
3. Test API connection with hardcoded sailing data

### Phase 2: Integration (Day 1-2)
4. Update `SailingViewModel` to include visual coach
5. Update `CoachInstructionPanesView` to accept recommendations
6. Wire up the data flow

### Phase 3: Polish (Day 2)
7. Add settings toggle
8. Add error handling and fallback logic
9. Test with simulator scenarios
10. Tune update interval if needed

---

## 10. Testing Checklist

- [ ] API returns valid JSON recommendations
- [ ] Panes update when recommendations change
- [ ] Timer fires every 10 seconds
- [ ] Fallback works when API is unavailable
- [ ] Both voice and visual coaches can run simultaneously
- [ ] Settings toggle works correctly
- [ ] No memory leaks (timer properly invalidated)

---

## Sources

- [Gemini 3 Flash Introduction](https://blog.google/products/gemini/gemini-3-flash/)
- [Gemini 3 Developer Guide](https://ai.google.dev/gemini-api/docs/gemini-3)
- [Gemini API Streaming with REST](https://github.com/google-gemini/cookbook/blob/main/quickstarts/rest/Streaming_REST.ipynb)
- [Integrating Gemini API into iOS with Swift](https://medium.com/@mortaltechnical/integrating-gemini-api-into-ios-application-using-swift-845d57a4b603)

# Gemini Live API - iOS Implementation Guide

Based on the Unity VR sailing simulator implementation, this document describes how to connect to the Gemini Live API for real-time voice conversations on iOS.

## Overview

The Gemini Live API uses WebSockets for bidirectional audio streaming. The connection flow is:
1. Open WebSocket with API key authentication
2. Send setup message with model and system instructions
3. Wait for `setupComplete` response
4. Stream audio bidirectionally (send microphone, receive AI voice)

## Connection Details

### WebSocket Endpoint
```
wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent?key=YOUR_API_KEY
```

### Authentication
**Method**: API key as URL query parameter

```swift
let apiKey = "YOUR_GEMINI_API_KEY"
let urlString = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent?key=\(apiKey)"
```

> **Security Note**: For production iOS apps, store the API key in the Keychain or fetch it from your backend server rather than hardcoding it.

## Audio Format Specifications

| Direction | Sample Rate | Format | Encoding |
|-----------|-------------|--------|----------|
| Input (mic → Gemini) | 16,000 Hz | PCM 16-bit signed, mono, little-endian | Base64 |
| Output (Gemini → speaker) | 24,000 Hz | PCM 16-bit signed, mono, little-endian | Base64 |

## Message Protocol

### 1. Setup Message (send after connection opens)

```json
{
  "setup": {
    "model": "models/gemini-live-2.5-flash-native-audio",
    "generation_config": {
      "response_modalities": ["AUDIO"]
    },
    "system_instruction": {
      "parts": {
        "text": "Your system prompt here..."
      }
    }
  }
}
```

### 2. Audio Input Message (microphone data)

```json
{
  "realtime_input": {
    "media_chunks": [
      {
        "data": "<base64_encoded_pcm_audio>",
        "mime_type": "audio/pcm"
      }
    ]
  }
}
```

### 3. Text/Context Message (optional state updates)

```json
{
  "client_content": {
    "turn_complete": "TRUE",
    "turns": [
      {
        "role": "user",
        "parts": [
          {
            "text": "Your context or instructions here"
          }
        ]
      }
    ]
  }
}
```

### 4. Response Format (from Gemini)

```json
{
  "serverContent": {
    "modelTurn": {
      "parts": [
        {
          "inlineData": {
            "mimeType": "audio/pcm",
            "data": "<base64_encoded_pcm_audio>"
          }
        }
      ]
    }
  }
}
```

## iOS Swift Implementation

### GeminiLiveClient.swift

```swift
import Foundation
import AVFoundation

class GeminiLiveClient: NSObject {

    // MARK: - Configuration
    private let apiKey: String
    private let model = "models/gemini-live-2.5-flash-native-audio"
    private let inputSampleRate: Double = 16000
    private let outputSampleRate: Double = 24000

    // MARK: - WebSocket
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession!

    // MARK: - Audio
    private var audioEngine: AVAudioEngine?
    private var audioPlayer: AVAudioPlayerNode?
    private var outputFormat: AVAudioFormat!
    private var isRecording = false

    // MARK: - Callbacks
    var onConnectionStateChanged: ((Bool) -> Void)?
    var onError: ((Error) -> Void)?

    init(apiKey: String) {
        self.apiKey = apiKey
        super.init()
        self.urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                          sampleRate: outputSampleRate,
                                          channels: 1,
                                          interleaved: false)!
    }

    // MARK: - Connection

    func connect(systemInstruction: String) {
        let urlString = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent?key=\(apiKey)"

        guard let url = URL(string: urlString) else {
            onError?(GeminiError.invalidURL)
            return
        }

        webSocket = urlSession.webSocketTask(with: url)
        webSocket?.resume()

        // Store system instruction for setup
        self.pendingSystemInstruction = systemInstruction

        // Start listening for messages
        receiveMessage()
    }

    private var pendingSystemInstruction: String?

    private func sendSetupMessage() {
        guard let systemInstruction = pendingSystemInstruction else { return }

        let setupMessage: [String: Any] = [
            "setup": [
                "model": model,
                "generation_config": [
                    "response_modalities": ["AUDIO"]
                ],
                "system_instruction": [
                    "parts": [
                        "text": systemInstruction
                    ]
                ]
            ]
        ]

        sendJSON(setupMessage)
    }

    func disconnect() {
        stopRecording()
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        onConnectionStateChanged?(false)
    }

    // MARK: - Message Handling

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let jsonString = String(data: data, encoding: .utf8) else {
            return
        }

        webSocket?.send(.string(jsonString)) { [weak self] error in
            if let error = error {
                self?.onError?(error)
            }
        }
    }

    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                self?.receiveMessage() // Continue listening

            case .failure(let error):
                self?.onError?(error)
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            if text.contains("setupComplete") {
                // Ready to start recording
                DispatchQueue.main.async {
                    self.startRecording()
                    self.onConnectionStateChanged?(true)
                }
            } else {
                // Parse audio response
                if let audioData = extractAudioData(from: text) {
                    playAudio(audioData)
                }
            }

        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                handleMessage(.string(text))
            }

        @unknown default:
            break
        }
    }

    private func extractAudioData(from json: String) -> Data? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let serverContent = dict["serverContent"] as? [String: Any],
              let modelTurn = serverContent["modelTurn"] as? [String: Any],
              let parts = modelTurn["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let inlineData = firstPart["inlineData"] as? [String: Any],
              let base64String = inlineData["data"] as? String,
              let audioData = Data(base64Encoded: base64String) else {
            return nil
        }
        return audioData
    }

    // MARK: - Audio Recording (Microphone Input)

    private func startRecording() {
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Convert to 16kHz mono for Gemini
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: inputSampleRate,
                                         channels: 1,
                                         interleaved: false)!

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            onError?(GeminiError.audioSetupFailed)
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.processInputBuffer(buffer, converter: converter, targetFormat: targetFormat)
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat)
            try AVAudioSession.sharedInstance().setActive(true)
            try audioEngine.start()
            isRecording = true
        } catch {
            onError?(error)
        }
    }

    private func processInputBuffer(_ buffer: AVAudioPCMBuffer,
                                    converter: AVAudioConverter,
                                    targetFormat: AVAudioFormat) {
        let frameCount = AVAudioFrameCount(targetFormat.sampleRate * Double(buffer.frameLength) / buffer.format.sampleRate)

        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else {
            return
        }

        var error: NSError?
        converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        if let error = error {
            onError?(error)
            return
        }

        // Convert float samples to 16-bit PCM and send
        sendAudioBuffer(convertedBuffer)
    }

    private func sendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let floatData = buffer.floatChannelData?[0] else { return }

        let frameLength = Int(buffer.frameLength)
        var pcmData = Data(capacity: frameLength * 2)

        for i in 0..<frameLength {
            // Convert float (-1.0 to 1.0) to 16-bit signed integer
            let sample = floatData[i]
            let clampedSample = max(-1.0, min(1.0, sample))
            let intSample = Int16(clampedSample * Float(Int16.max))

            // Little-endian
            pcmData.append(UInt8(intSample & 0xFF))
            pcmData.append(UInt8((intSample >> 8) & 0xFF))
        }

        let base64Audio = pcmData.base64EncodedString()

        let audioMessage: [String: Any] = [
            "realtime_input": [
                "media_chunks": [
                    [
                        "data": base64Audio,
                        "mime_type": "audio/pcm"
                    ]
                ]
            ]
        ]

        sendJSON(audioMessage)
    }

    private func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        isRecording = false
    }

    // MARK: - Audio Playback (Gemini Response)

    private func playAudio(_ pcmData: Data) {
        // Convert 16-bit PCM to float samples
        let sampleCount = pcmData.count / 2
        var floatSamples = [Float](repeating: 0, count: sampleCount)

        pcmData.withUnsafeBytes { rawBuffer in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                floatSamples[i] = Float(int16Buffer[i]) / Float(Int16.max)
            }
        }

        // Create audio buffer and play
        guard let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat,
                                            frameCapacity: AVAudioFrameCount(sampleCount)) else {
            return
        }

        buffer.frameLength = AVAudioFrameCount(sampleCount)
        if let channelData = buffer.floatChannelData?[0] {
            for i in 0..<sampleCount {
                channelData[i] = floatSamples[i]
            }
        }

        DispatchQueue.main.async {
            self.scheduleAudioPlayback(buffer)
        }
    }

    private func scheduleAudioPlayback(_ buffer: AVAudioPCMBuffer) {
        if audioPlayer == nil {
            audioPlayer = AVAudioPlayerNode()
            audioEngine?.attach(audioPlayer!)
            audioEngine?.connect(audioPlayer!, to: audioEngine!.mainMixerNode, format: outputFormat)
        }

        audioPlayer?.scheduleBuffer(buffer, completionHandler: nil)

        if audioPlayer?.isPlaying == false {
            audioPlayer?.play()
        }
    }

    // MARK: - Send Context/State Updates

    func sendTextMessage(_ text: String) {
        let message: [String: Any] = [
            "client_content": [
                "turn_complete": "TRUE",
                "turns": [
                    [
                        "role": "user",
                        "parts": [
                            ["text": text]
                        ]
                    ]
                ]
            ]
        ]

        sendJSON(message)
    }
}

// MARK: - URLSessionWebSocketDelegate

extension GeminiLiveClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        sendSetupMessage()
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        DispatchQueue.main.async {
            self.onConnectionStateChanged?(false)
        }
    }
}

// MARK: - Errors

enum GeminiError: Error {
    case invalidURL
    case audioSetupFailed
}
```

### Usage Example

```swift
class SailingCoachViewController: UIViewController {

    private var geminiClient: GeminiLiveClient!

    override func viewDidLoad() {
        super.viewDidLoad()

        geminiClient = GeminiLiveClient(apiKey: "YOUR_API_KEY")

        geminiClient.onConnectionStateChanged = { isConnected in
            print("Connected: \(isConnected)")
        }

        geminiClient.onError = { error in
            print("Error: \(error)")
        }
    }

    func startCoaching() {
        let systemPrompt = """
        You are a sailing instructor teaching a first-time sailor.
        Provide clear, concise voice guidance.
        """

        geminiClient.connect(systemInstruction: systemPrompt)
    }

    func sendSailingState(windAngle: Float, speed: Float, heading: Float) {
        let stateMessage = """
        Current sailing state: Wind angle \(windAngle)°, Speed \(speed) knots, Heading \(heading)°
        """
        geminiClient.sendTextMessage(stateMessage)
    }

    func stopCoaching() {
        geminiClient.disconnect()
    }
}
```

### Info.plist Required Keys

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Microphone access is needed for voice communication with the AI sailing coach.</string>
```

## Key Differences from Unity Implementation

| Aspect | Unity | iOS |
|--------|-------|-----|
| WebSocket library | NativeWebSocket | URLSessionWebSocketTask |
| Audio capture | Unity Microphone API | AVAudioEngine |
| Audio playback | AudioSource + circular buffer | AVAudioPlayerNode |
| JSON parsing | JsonUtility / Newtonsoft | JSONSerialization |
| Threading | Unity main thread dispatch | DispatchQueue |

## Source Files Reference

The Unity implementation this guide is based on:

| File | Purpose |
|------|---------|
| `Assets/SailSim/Scripts/AI/GeminiVoiceChat.cs` | WebSocket connection and audio streaming |
| `Assets/SailSim/Scripts/AI/GeminiResponse.cs` | JSON response parsing |
| `Assets/SailSim/Scripts/AI/Voice3D.cs` | Audio playback with circular buffer |
| `Assets/SailSim/Scripts/AI/AIInstructor.cs` | State management and update triggers |

## Notes

- The API key is passed directly in the URL query string - this is the same authentication method used in the Unity implementation
- Audio must be streamed continuously while the connection is open
- The `setupComplete` message indicates the session is ready for audio input
- Consider implementing a circular buffer for smoother audio playback (as done in `Voice3D.cs` in the Unity version)

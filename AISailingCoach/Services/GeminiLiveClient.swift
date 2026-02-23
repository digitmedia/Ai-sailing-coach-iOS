//
//  GeminiLiveClient.swift
//  AISailingCoach
//
//  Gemini Live API client for real-time voice conversations
//  Based on the Unity VR sailing simulator implementation
//

import Foundation
import AVFoundation

/// Client for Gemini Live API with native audio support
class GeminiLiveClient: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published var isConnected = false
    @Published var isRecording = false
    @Published var connectionState: ConnectionState = .disconnected

    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    // MARK: - Configuration

    private let apiKey: String
    private let model = "models/gemini-2.5-flash-native-audio-preview-12-2025"  // Latest native audio model
    private let inputSampleRate: Double = 16000  // Mic → Gemini
    private let outputSampleRate: Double = 24000 // Gemini → Speaker

    // MARK: - WebSocket

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var pendingSystemInstruction: String?

    // MARK: - Audio Engine

    private var audioEngine: AVAudioEngine?
    private var audioPlayer: AVAudioPlayerNode?
    private var outputFormat: AVAudioFormat!
    private var inputConverter: AVAudioConverter?

    // MARK: - Turn Management (prevents echo/feedback)

    private var isModelSpeaking = false  // Pause mic input while model speaks

    // MARK: - Callbacks

    var onConnectionStateChanged: ((Bool) -> Void)?
    var onError: ((Error) -> Void)?
    var onTranscript: ((String) -> Void)?

    // MARK: - Initialization

    init(apiKey: String) {
        self.apiKey = apiKey
        super.init()

        // Create URL session with delegate for WebSocket events
        self.urlSession = URLSession(
            configuration: .default,
            delegate: self,
            delegateQueue: OperationQueue()
        )

        // Output format for playback (24kHz mono float)
        self.outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: outputSampleRate,
            channels: 1,
            interleaved: false
        )!
    }

    // MARK: - Connection

    func connect(systemInstruction: String) {
        // Use v1alpha endpoint for native audio models
        let urlString = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent?key=\(apiKey)"

        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                self.connectionState = .error("Invalid URL")
            }
            onError?(GeminiLiveError.invalidURL)
            return
        }

        print("🔌 Connecting to Gemini Live API...")
        print("🔌 URL: \(url.host ?? "")")

        DispatchQueue.main.async {
            self.connectionState = .connecting
        }

        // Store system instruction for setup message
        self.pendingSystemInstruction = systemInstruction

        // Create and start WebSocket
        webSocket = urlSession.webSocketTask(with: url)
        webSocket?.resume()

        // Start listening for messages
        receiveMessage()
    }

    func disconnect() {
        print("🔌 Disconnecting...")
        isModelSpeaking = false
        stopRecording()
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil

        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionState = .disconnected
        }
        onConnectionStateChanged?(false)
    }

    // MARK: - Setup Message

    private func sendSetupMessage() {
        guard let systemInstruction = pendingSystemInstruction else {
            print("❌ No system instruction")
            return
        }

        print("📤 Sending setup message...")
        print("📤 Model: \(model)")

        // Full setup message with system instruction and VAD config
        let setupMessage: [String: Any] = [
            "setup": [
                "model": model,
                "generationConfig": [
                    "responseModalities": ["AUDIO"]
                ],
                "systemInstruction": [
                    "parts": [
                        ["text": systemInstruction]
                    ]
                ],
                "realtimeInputConfig": [
                    "automaticActivityDetection": [
                        "disabled": false,
                        "startOfSpeechSensitivity": "START_SENSITIVITY_LOW",
                        "endOfSpeechSensitivity": "END_SENSITIVITY_LOW",
                        "prefixPaddingMs": 100,
                        "silenceDurationMs": 500
                    ]
                ]
            ]
        ]

        print("📤 System instruction: \(systemInstruction.prefix(100))...")

        // Debug: print the JSON being sent
        if let data = try? JSONSerialization.data(withJSONObject: setupMessage, options: .prettyPrinted),
           let jsonString = String(data: data, encoding: .utf8) {
            print("📤 Setup JSON:\n\(jsonString)")
        }

        sendJSON(setupMessage)
    }

    // MARK: - Message Sending

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let jsonString = String(data: data, encoding: .utf8) else {
            print("❌ Failed to serialize JSON")
            return
        }

        webSocket?.send(.string(jsonString)) { [weak self] error in
            if let error = error {
                print("❌ Send error: \(error)")
                self?.onError?(error)
            }
        }
    }

    /// Send text message (for context updates)
    func sendTextMessage(_ text: String) {
        let message: [String: Any] = [
            "client_content": [
                "turn_complete": true,
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

    // MARK: - Message Receiving

    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                self?.receiveMessage() // Continue listening

            case .failure(let error):
                print("❌ Receive error: \(error)")
                self?.onError?(error)
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        var text: String?

        switch message {
        case .string(let str):
            text = str
        case .data(let data):
            text = String(data: data, encoding: .utf8)
        @unknown default:
            return
        }

        guard let jsonText = text else { return }

        // Check for setupComplete
        if jsonText.contains("setupComplete") {
            print("✅ Setup complete - starting audio")
            DispatchQueue.main.async {
                self.isConnected = true
                self.connectionState = .connected
                self.startRecording()
            }
            onConnectionStateChanged?(true)
            return
        }

        // Check for turn complete (model finished speaking)
        if jsonText.contains("\"turnComplete\"") {
            isModelSpeaking = false
            print("🔇 Model turn complete - resuming mic")
        }

        // Parse and play audio response
        if let audioData = extractAudioData(from: jsonText) {
            // Model is speaking - pause mic input to prevent echo
            if !isModelSpeaking {
                isModelSpeaking = true
                print("🔊 Model speaking - pausing mic")
            }
            playAudio(audioData)
        }

        // Extract text transcript if available
        if let transcript = extractTranscript(from: jsonText) {
            DispatchQueue.main.async {
                self.onTranscript?(transcript)
            }
        }
    }

    private func extractAudioData(from json: String) -> Data? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let serverContent = dict["serverContent"] as? [String: Any],
              let modelTurn = serverContent["modelTurn"] as? [String: Any],
              let parts = modelTurn["parts"] as? [[String: Any]] else {
            return nil
        }

        for part in parts {
            if let inlineData = part["inlineData"] as? [String: Any],
               let base64String = inlineData["data"] as? String,
               let audioData = Data(base64Encoded: base64String) {
                return audioData
            }
        }

        return nil
    }

    private func extractTranscript(from json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let serverContent = dict["serverContent"] as? [String: Any],
              let modelTurn = serverContent["modelTurn"] as? [String: Any],
              let parts = modelTurn["parts"] as? [[String: Any]] else {
            return nil
        }

        for part in parts {
            if let text = part["text"] as? String {
                return text
            }
        }

        return nil
    }

    // MARK: - Audio Recording (Microphone → Gemini)

    private func startRecording() {
        print("🎙️ Starting audio recording...")

        // IMPORTANT: Configure audio session FIRST, before creating the audio engine
        // This ensures the hardware sample rate is set before we query it
        do {
            let audioSession = AVAudioSession.sharedInstance()

            // Set preferred sample rate to 48kHz (standard iOS rate that works well)
            try audioSession.setPreferredSampleRate(48000)

            // Configure for voice chat with speaker output
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try audioSession.setActive(true)

            print("🎙️ Audio session configured: \(audioSession.sampleRate)Hz")
        } catch {
            print("❌ Audio session setup error: \(error)")
            onError?(error)
            return
        }

        // Now create the audio engine after session is configured
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }

        let inputNode = audioEngine.inputNode

        // Get the actual hardware format after audio session is configured
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        print("🎙️ Hardware input format: \(hardwareFormat.sampleRate)Hz, \(hardwareFormat.channelCount) channels")

        // Use the node's output format which should match what we can tap
        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("🎙️ Input node output format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")

        // Target format: 16kHz mono float (for conversion to PCM)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            print("❌ Failed to create target format")
            return
        }

        // Create converter from input format to target format
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            print("❌ Failed to create audio converter from \(inputFormat.sampleRate)Hz to \(targetFormat.sampleRate)Hz")
            onError?(GeminiLiveError.audioSetupFailed)
            return
        }
        self.inputConverter = converter

        // Setup audio player for output BEFORE starting the engine
        audioPlayer = AVAudioPlayerNode()
        audioEngine.attach(audioPlayer!)
        audioEngine.connect(audioPlayer!, to: audioEngine.mainMixerNode, format: outputFormat)

        // Prepare the engine (this helps prevent format mismatches)
        audioEngine.prepare()

        do {
            try audioEngine.start()
            print("✅ Audio engine started")
        } catch {
            print("❌ Audio engine start error: \(error)")
            onError?(error)
            return
        }

        // Install tap AFTER the engine is started
        // Use nil format to let the system choose the best format for the tap
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self = self else { return }
            // Skip sending audio while model is speaking (prevents echo)
            guard !self.isModelSpeaking else { return }
            self.processInputBuffer(buffer, converter: converter, targetFormat: targetFormat)
        }

        audioPlayer?.play()

        DispatchQueue.main.async {
            self.isRecording = true
        }
        print("✅ Audio recording started")
    }

    private func processInputBuffer(_ buffer: AVAudioPCMBuffer,
                                    converter: AVAudioConverter,
                                    targetFormat: AVAudioFormat) {
        // If formats match the converter's input, use the converter
        // Otherwise, we need to handle the format difference
        let bufferFormat = buffer.format

        // Calculate frame count for converted buffer
        let ratio = targetFormat.sampleRate / bufferFormat.sampleRate
        let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard frameCount > 0 else { return }

        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else {
            return
        }

        // Check if we need to create a new converter for this buffer format
        let currentConverter: AVAudioConverter
        if bufferFormat.sampleRate == converter.inputFormat.sampleRate &&
           bufferFormat.channelCount == converter.inputFormat.channelCount {
            currentConverter = converter
        } else {
            // Create a new converter for the actual buffer format
            guard let newConverter = AVAudioConverter(from: bufferFormat, to: targetFormat) else {
                print("❌ Failed to create converter for format: \(bufferFormat.sampleRate)Hz")
                return
            }
            currentConverter = newConverter
        }

        var error: NSError?
        var inputBufferConsumed = false

        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if inputBufferConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputBufferConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        let status = currentConverter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            print("❌ Conversion error: \(error)")
            return
        }

        if status == .error {
            print("❌ Conversion status error")
            return
        }

        // Send converted audio to Gemini
        sendAudioBuffer(convertedBuffer)
    }

    private func sendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let floatData = buffer.floatChannelData?[0] else { return }

        let frameLength = Int(buffer.frameLength)
        var pcmData = Data(capacity: frameLength * 2)

        // Convert float samples to 16-bit PCM little-endian
        for i in 0..<frameLength {
            let sample = floatData[i]
            let clampedSample = max(-1.0, min(1.0, sample))
            let intSample = Int16(clampedSample * Float(Int16.max))

            // Little-endian byte order
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
        print("🎙️ Stopping recording...")
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioPlayer?.stop()
        audioPlayer = nil
        audioEngine = nil

        DispatchQueue.main.async {
            self.isRecording = false
        }
    }

    // MARK: - Audio Playback (Gemini → Speaker)

    private func playAudio(_ pcmData: Data) {
        print("🔊 Playing audio: \(pcmData.count) bytes")

        guard let player = audioPlayer, let engine = audioEngine, engine.isRunning else {
            print("❌ Audio engine not ready for playback")
            return
        }

        // Convert 16-bit PCM to float samples
        let sampleCount = pcmData.count / 2
        var floatSamples = [Float](repeating: 0, count: sampleCount)

        pcmData.withUnsafeBytes { rawBuffer in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                floatSamples[i] = Float(int16Buffer[i]) / Float(Int16.max)
            }
        }

        // Create audio buffer
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

        // Schedule buffer for playback
        player.scheduleBuffer(buffer) {
            print("🔊 Buffer finished playing")
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension GeminiLiveClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        print("✅ WebSocket connected")
        sendSetupMessage()
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        print("🔌 WebSocket closed: \(closeCode)")
        if let reason = reason, let reasonString = String(data: reason, encoding: .utf8) {
            print("🔌 Close reason: \(reasonString)")
        }
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionState = .disconnected
        }
        onConnectionStateChanged?(false)
    }
}

// MARK: - Errors

enum GeminiLiveError: LocalizedError {
    case invalidURL
    case audioSetupFailed
    case connectionFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Gemini API URL"
        case .audioSetupFailed: return "Failed to setup audio"
        case .connectionFailed: return "Failed to connect to Gemini Live"
        }
    }
}

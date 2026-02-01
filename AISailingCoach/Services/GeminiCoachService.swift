//
//  GeminiCoachService.swift
//  AISailingCoach
//
//  Integration with Google Gemini Live API for real-time AI sailing coaching
//  Provides voice-based coaching during sailing with context-aware responses
//

import Foundation
import Combine
import AVFoundation

/// Service for interacting with Gemini Live API for sailing coaching
@MainActor
class GeminiCoachService: ObservableObject {
    // MARK: - Published Properties

    @Published var currentResponse: String = ""
    @Published var connectionState: CoachState = .idle
    @Published var isConfigured: Bool = false

    // MARK: - Private Properties

    private var apiKey: String?
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?

    // Lazy-loaded speech service to avoid audio init issues on simulator
    private var _speechService: SpeechService?
    private var speechService: SpeechService {
        if _speechService == nil {
            _speechService = SpeechService()
        }
        return _speechService!
    }

    // Gemini Live API endpoint
    private let baseURL = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent"

    // System prompt for sailing coach persona
    private let systemPrompt = """
    You are an expert sailing coach with decades of racing experience. You're currently on a racing sailboat helping the crew optimize their performance during a regatta.

    Your role:
    - Provide tactical sailing advice based on current conditions
    - Help optimize boat speed and VMG (Velocity Made Good)
    - Suggest sail trim adjustments
    - Advise on laylines and wind shifts
    - Keep responses brief and actionable (2-3 sentences max)
    - Use proper sailing terminology
    - Be encouraging but focused on performance

    Current boat data will be provided with each query. Use this data to give relevant, contextual advice.

    Speak naturally as if you're on the boat. Keep it brief - sailors are busy!
    """

    // MARK: - Initialization

    init() {
        // Don't initialize speech service here - it's lazy loaded
        loadStoredAPIKey()
    }

    // MARK: - Configuration

    func configure(apiKey: String) {
        self.apiKey = apiKey
        isConfigured = !apiKey.isEmpty
        storeAPIKey(apiKey)
    }

    private func loadStoredAPIKey() {
        // Load from UserDefaults (in production, use Keychain)
        if let key = UserDefaults.standard.string(forKey: "GeminiAPIKey"), !key.isEmpty {
            self.apiKey = key
            isConfigured = true
        }
    }

    private func storeAPIKey(_ key: String) {
        // Store in UserDefaults (in production, use Keychain)
        UserDefaults.standard.set(key, forKey: "GeminiAPIKey")
    }

    // MARK: - Voice Interaction

    func startListening(context: CoachContext) {
        guard isConfigured else {
            connectionState = .error
            currentResponse = "Please configure your Gemini API key in Settings"
            return
        }

        connectionState = .listening
        speechService.startListening { [weak self] transcription in
            guard let self = self, let text = transcription else { return }
            Task {
                await self.sendQuery(text, context: context)
            }
        }
    }

    func stopListening() {
        _speechService?.stopListening()
        if connectionState == .listening {
            connectionState = .idle
        }
    }

    // MARK: - Query Handling

    func sendQuery(_ query: String, context: CoachContext) async {
        guard let apiKey = apiKey else {
            connectionState = .error
            currentResponse = "API key not configured"
            return
        }

        connectionState = .processing

        // Build the prompt with context
        let fullPrompt = """
        \(context.description)

        Sailor's question: \(query)
        """

        do {
            let response = try await sendToGemini(prompt: fullPrompt, apiKey: apiKey)
            currentResponse = response

            connectionState = .speaking
            await speechService.speak(response)
            connectionState = .idle

        } catch {
            connectionState = .error
            currentResponse = "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Gemini API Communication

    private func sendToGemini(prompt: String, apiKey: String) async throws -> String {
        // Using REST API for simplicity (Live API would use WebSocket)
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": systemPrompt],
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 150,
                "topP": 0.9
            ],
            "safetySettings": [
                ["category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_NONE"],
                ["category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_NONE"],
                ["category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_NONE"],
                ["category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_NONE"]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        // Parse response
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let candidates = json?["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw GeminiError.parseError
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Gemini Live API (WebSocket) - For future real-time audio

    func connectLive(context: CoachContext) async throws {
        guard let apiKey = apiKey else {
            throw GeminiError.notConfigured
        }

        let urlString = "\(baseURL)?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw GeminiError.invalidURL
        }

        session = URLSession(configuration: .default)
        webSocketTask = session?.webSocketTask(with: url)
        webSocketTask?.resume()

        // Send setup message
        let setupMessage: [String: Any] = [
            "setup": [
                "model": "models/gemini-2.0-flash-exp",
                "generationConfig": [
                    "responseModalities": ["AUDIO"],
                    "speechConfig": [
                        "voiceConfig": [
                            "prebuiltVoiceConfig": [
                                "voiceName": "Kore"
                            ]
                        ]
                    ]
                ],
                "systemInstruction": [
                    "parts": [
                        ["text": systemPrompt]
                    ]
                ]
            ]
        ]

        let setupData = try JSONSerialization.data(withJSONObject: setupMessage)
        try await webSocketTask?.send(.data(setupData))

        connectionState = .listening
        receiveMessages()
    }

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleWebSocketMessage(message)
                self?.receiveMessages() // Continue receiving
            case .failure(let error):
                print("WebSocket error: \(error)")
                Task { @MainActor in
                    self?.connectionState = .error
                }
            }
        }
    }

    private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            parseGeminiResponse(data)
        case .string(let text):
            if let data = text.data(using: .utf8) {
                parseGeminiResponse(data)
            }
        @unknown default:
            break
        }
    }

    private func parseGeminiResponse(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // Handle different response types
        if let serverContent = json["serverContent"] as? [String: Any],
           let modelTurn = serverContent["modelTurn"] as? [String: Any],
           let parts = modelTurn["parts"] as? [[String: Any]] {

            for part in parts {
                if let text = part["text"] as? String {
                    Task { @MainActor in
                        self.currentResponse = text
                    }
                }
                // Handle audio data if present
                if let inlineData = part["inlineData"] as? [String: Any],
                   let audioData = inlineData["data"] as? String {
                    // Decode and play audio
                    handleAudioResponse(base64Audio: audioData)
                }
            }
        }
    }

    private func handleAudioResponse(base64Audio: String) {
        guard let audioData = Data(base64Encoded: base64Audio) else { return }
        // Play audio through AVAudioPlayer
        Task { @MainActor in
            speechService.playAudioData(audioData)
        }
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectionState = .idle
    }
}

// MARK: - Error Types

enum GeminiError: LocalizedError {
    case notConfigured
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Gemini API key not configured"
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from API"
        case .apiError(let code, let message):
            return "API Error (\(code)): \(message)"
        case .parseError:
            return "Failed to parse API response"
        }
    }
}

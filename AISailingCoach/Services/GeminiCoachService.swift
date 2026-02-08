//
//  GeminiCoachService.swift
//  AISailingCoach
//
//  Integration with Google Gemini Live API for real-time AI sailing coaching
//  Uses WebSocket connection for bidirectional audio/text streaming
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
    @Published var isConnected: Bool = false

    // MARK: - Private Properties

    private var apiKey: String?
    private var geminiLiveClient: GeminiLiveClient?
    private var currentContext: CoachContext?
    private var isSessionActive = false
    private var cancellables = Set<AnyCancellable>()

    // Timer for periodic data updates
    private var dataUpdateTimer: Timer?
    private let dataUpdateInterval: TimeInterval = 10.0  // Send data every 10 seconds

    // Callback to get fresh sailing data
    var getSailingData: (() -> CoachContext)?

    // Lazy-loaded speech service (for REST API fallback only)
    private var _speechService: SpeechService?
    private var speechService: SpeechService {
        if _speechService == nil {
            _speechService = SpeechService()
        }
        return _speechService!
    }

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
        loadStoredAPIKey()
    }

    // MARK: - Configuration

    func configure(apiKey: String) {
        self.apiKey = apiKey
        isConfigured = !apiKey.isEmpty
        storeAPIKey(apiKey)
    }

    private func loadStoredAPIKey() {
        if let key = UserDefaults.standard.string(forKey: "GeminiAPIKey"), !key.isEmpty {
            self.apiKey = key
            isConfigured = true
        }
    }

    private func storeAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "GeminiAPIKey")
    }

    // MARK: - Live Session Management

    func startLiveSession(context: CoachContext) async {
        // Prevent duplicate connections
        guard !isSessionActive else {
            print("⚠️ Session already active, ignoring start request")
            return
        }

        guard isConfigured, let apiKey = apiKey, !apiKey.isEmpty else {
            connectionState = .error
            currentResponse = "Please configure your Gemini API key in Settings"
            return
        }

        print("🎙️ Starting live session with Gemini Live API")

        // Clean up any existing client first
        geminiLiveClient?.disconnect()
        geminiLiveClient = nil

        isSessionActive = true
        currentContext = context
        connectionState = .processing
        currentResponse = "Connecting to AI Coach..."

        // Create the Gemini Live client
        geminiLiveClient = GeminiLiveClient(apiKey: apiKey)

        // Setup callbacks
        geminiLiveClient?.onConnectionStateChanged = { [weak self] connected in
            DispatchQueue.main.async {
                self?.isConnected = connected
                if connected {
                    self?.connectionState = .listening
                    self?.currentResponse = "Connected! Speak your question..."

                    // Send initial sailing context
                    let contextMessage = context.description
                    self?.geminiLiveClient?.sendTextMessage(contextMessage)

                    // Start periodic data updates
                    self?.startDataUpdateTimer()
                } else if self?.isSessionActive == true {
                    self?.connectionState = .error
                    self?.currentResponse = "Connection lost"
                    self?.stopDataUpdateTimer()
                }
            }
        }

        geminiLiveClient?.onTranscript = { [weak self] text in
            DispatchQueue.main.async {
                self?.currentResponse = text
                self?.connectionState = .speaking
            }
        }

        geminiLiveClient?.onError = { [weak self] error in
            print("❌ Gemini Live error: \(error)")
            DispatchQueue.main.async {
                guard self?.isSessionActive == true else { return }

                // Fall back to REST API
                self?.currentResponse = "Using voice mode..."
                self?.startSpeechRecognition(context: context)
            }
        }

        // Build system instruction with sailing coach persona
        let fullSystemInstruction = """
        \(systemPrompt)

        Current sailing conditions:
        \(context.description)
        """

        // Connect!
        geminiLiveClient?.connect(systemInstruction: fullSystemInstruction)
    }

    private func startSpeechRecognition(context: CoachContext) {
        guard isSessionActive else { return }

        connectionState = .listening
        currentResponse = "Listening... Ask me anything!"

        speechService.startListening { [weak self] transcribedText in
            guard let self = self else { return }

            Task { @MainActor in
                // Double-check session is still active
                guard self.isSessionActive else {
                    print("Session ended, ignoring transcription")
                    return
                }

                if let text = transcribedText, !text.isEmpty {
                    self.currentResponse = "You asked: \"\(text)\""
                    await self.sendQueryREST(text, context: context)
                }
                // Note: Don't auto-restart listening - user needs to tap again for next question
            }
        }
    }

    func endLiveSession() {
        guard isSessionActive else {
            print("⚠️ Session already ended")
            return
        }

        print("🛑 Ending live session")
        isSessionActive = false

        // Stop periodic data updates
        stopDataUpdateTimer()

        // Disconnect Gemini Live client
        geminiLiveClient?.disconnect()
        geminiLiveClient = nil

        // Stop fallback speech service if running
        speechService.stopListening()

        // Reset state
        connectionState = .idle
        currentResponse = ""
        isConnected = false
    }

    // MARK: - Periodic Data Updates

    private func startDataUpdateTimer() {
        stopDataUpdateTimer()  // Clear any existing timer

        print("⏱️ Starting data update timer (every \(dataUpdateInterval)s)")

        dataUpdateTimer = Timer.scheduledTimer(withTimeInterval: dataUpdateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendDataUpdate()
            }
        }
    }

    private func stopDataUpdateTimer() {
        dataUpdateTimer?.invalidate()
        dataUpdateTimer = nil
        print("⏱️ Data update timer stopped")
    }

    private func sendDataUpdate() {
        guard isSessionActive, isConnected, let client = geminiLiveClient else { return }

        // Get fresh sailing data from the callback
        let context: CoachContext
        if let getSailingData = getSailingData {
            context = getSailingData()
        } else if let currentContext = currentContext {
            context = currentContext
        } else {
            return
        }

        // Update stored context
        self.currentContext = context

        // Format as a data update message
        let updateMessage = """
        [SAILING DATA UPDATE]
        \(context.description)
        """

        print("📊 Sending data update to coach")
        client.sendTextMessage(updateMessage)
    }

    /// Update the sailing context (can be called externally to push immediate updates)
    func updateContext(_ context: CoachContext) {
        self.currentContext = context

        // If connected, send the update immediately
        if isConnected, let client = geminiLiveClient {
            let updateMessage = """
            [SAILING DATA UPDATE]
            \(context.description)
            """
            client.sendTextMessage(updateMessage)
        }
    }

    // MARK: - Send Text Message (for context updates)

    func sendTextMessage(_ text: String) async {
        // Send via Gemini Live client if connected
        if isConnected, let client = geminiLiveClient {
            client.sendTextMessage(text)
            return
        }

        // Fall back to REST API if not connected
        if let context = currentContext {
            await sendQueryREST(text, context: context)
        }
    }

    // MARK: - Fallback REST API (for error recovery)

    private func sendQueryREST(_ query: String, context: CoachContext) async {
        guard let apiKey = apiKey else {
            connectionState = .error
            currentResponse = "API key not configured"
            return
        }

        guard isSessionActive else { return }

        connectionState = .processing
        currentResponse = "Thinking..."

        let fullPrompt = """
        \(context.description)

        Sailor's question: \(query)
        """

        do {
            // Get text response from Gemini
            let text = try await callGeminiREST(prompt: fullPrompt, apiKey: apiKey)

            guard isSessionActive else { return }

            currentResponse = text
            connectionState = .speaking

            // Use iOS TTS for simulator fallback
            // Native audio is only available via WebSocket on real device
            await speechService.speak(text)

            guard isSessionActive else { return }
            connectionState = .listening
            currentResponse = "Tap ✨ to ask another question"

        } catch {
            connectionState = .error
            currentResponse = "Error: \(error.localizedDescription)"
        }
    }

    private func callGeminiREST(prompt: String, apiKey: String) async throws -> String {
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
                "maxOutputTokens": 150
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GeminiError.invalidResponse
        }

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
}

// MARK: - Error Types

enum GeminiError: LocalizedError {
    case notConfigured
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parseError
    case connectionFailed

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
        case .connectionFailed:
            return "Failed to connect to Gemini Live"
        }
    }
}

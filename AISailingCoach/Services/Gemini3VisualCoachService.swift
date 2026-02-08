//
//  Gemini3VisualCoachService.swift
//  AISailingCoach
//
//  Visual coaching service using Gemini 3 Flash API
//  Provides sailing recommendations for the 4 UI panes every 10 seconds
//

import Foundation
import Combine

/// Service for getting visual sailing recommendations from Gemini 3 Flash
@MainActor
class Gemini3VisualCoachService: ObservableObject {

    // MARK: - Published Properties

    @Published var recommendations: CoachRecommendations?
    /// Whether the visual coach service is currently running
    @Published var isActive: Bool = false
    @Published var lastError: String?
    @Published var isLoading: Bool = false

    // MARK: - Configuration

    // Using Gemini 3 Flash preview
    private let model = "gemini-3-flash-preview"
    private let updateInterval: TimeInterval = 10.0  // Update every 10 seconds
    private var apiKey: String?
    private var updateTimer: Timer?

    // Callback to get fresh sailing data
    var getSailingData: (() -> SailingData)?

    // MARK: - System Prompt

    private let systemPrompt = """
    You are a sailing coach. Analyze the boat data and recommend:
    - recommendedHeadsail: "genoa" if TWA<50°, "code0" if TWA 50-90°, "gennaker" if TWA>90°
    - steeringRecommendation: "steady" if performance>=95%, otherwise "bearAway" to build speed
    - sailTrimRecommendation: "hold" if performance>=95%, "ease" if performance<90%, otherwise "sheetIn"
    """

    // MARK: - Initialization

    init() {
        loadStoredAPIKey()
    }

    private func loadStoredAPIKey() {
        if let key = UserDefaults.standard.string(forKey: "GeminiAPIKey"), !key.isEmpty {
            self.apiKey = key
        }
    }

    func configure(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Service Control

    func start() {
        guard !isActive else {
            print("⚠️ Visual coach already active")
            return
        }

        guard apiKey != nil else {
            lastError = "API key not configured"
            print("❌ Visual coach: API key not configured")
            return
        }

        print("🎯 Starting Gemini 3 Visual Coach (updates every \(updateInterval)s)")
        isActive = true
        lastError = nil

        // Fetch immediately on start
        Task {
            await fetchRecommendations()
        }

        // Then start periodic updates
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchRecommendations()
            }
        }
    }

    func stop() {
        print("🛑 Stopping Gemini 3 Visual Coach")
        updateTimer?.invalidate()
        updateTimer = nil
        isActive = false
        isLoading = false
    }

    // MARK: - API Call

    private func fetchRecommendations() async {
        guard let apiKey = apiKey else {
            lastError = "API key not configured"
            return
        }

        guard let getSailingData = getSailingData else {
            lastError = "No sailing data callback configured"
            return
        }

        let sailingData = getSailingData()
        isLoading = true

        // Build the prompt with current sailing data
        let dataPrompt = buildDataPrompt(from: sailingData)

        print("📊 Visual coach: speed=\(String(format: "%.1f", sailingData.boatSpeed))kts, perf=\(sailingData.performance)%, TWA=\(Int(sailingData.trueWindAngle))°")

        // Try API call, but also calculate fallback
        let fallback = CoachRecommendations.calculateFallback(from: sailingData)

        do {
            let response = try await callGemini3API(prompt: dataPrompt, apiKey: apiKey)

            // Check if response contains actual JSON
            if response.contains("{") && response.contains("}") {
                print("📥 API Response: \(response)")
                let newRecommendations = try parseRecommendations(from: response)
                self.recommendations = newRecommendations
                self.lastError = nil
                print("✅ API: headsail=\(newRecommendations.recommendedHeadsail.rawValue), steering=\(newRecommendations.steeringRecommendation.rawValue), trim=\(newRecommendations.sailTrimRecommendation.rawValue)")
            } else {
                // API returned but no JSON - use fallback
                print("⚠️ API response incomplete: \(response.prefix(50))...")
                self.recommendations = fallback
                print("📍 Using fallback: headsail=\(fallback.recommendedHeadsail.rawValue), steering=\(fallback.steeringRecommendation.rawValue), trim=\(fallback.sailTrimRecommendation.rawValue)")
            }
        } catch {
            print("❌ API error: \(error.localizedDescription)")
            self.lastError = error.localizedDescription
            self.recommendations = fallback
            print("📍 Using fallback: headsail=\(fallback.recommendedHeadsail.rawValue), steering=\(fallback.steeringRecommendation.rawValue), trim=\(fallback.sailTrimRecommendation.rawValue)")
        }

        isLoading = false
    }

    private func buildDataPrompt(from data: SailingData) -> String {
        // Match the few-shot format exactly
        "Input: speed=\(String(format: "%.1f", data.boatSpeed))kts, perf=\(data.performance)%, TWA=\(Int(data.trueWindAngle))°\nOutput:"
    }

    // MARK: - Gemini 3 Flash API

    private func callGemini3API(prompt: String, apiKey: String) async throws -> String {
        // Use generateContent endpoint with JSON response mode and schema
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"

        guard let url = URL(string: urlString) else {
            throw VisualCoachError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15 // 15 second timeout

        // Build JSON Schema for structured output (per Gemini 3 docs)
        // Using responseMimeType + responseSchema guarantees valid JSON output
        let jsonSchema: [String: Any] = [
            "type": "OBJECT",
            "properties": [
                "recommendedHeadsail": [
                    "type": "STRING",
                    "enum": ["genoa", "code0", "gennaker"]
                ],
                "steeringRecommendation": [
                    "type": "STRING",
                    "enum": ["steady", "headUp", "bearAway"]
                ],
                "sailTrimRecommendation": [
                    "type": "STRING",
                    "enum": ["hold", "sheetIn", "ease"]
                ]
            ],
            "required": ["recommendedHeadsail", "steeringRecommendation", "sailTrimRecommendation"]
        ]

        // Request body with response_schema for guaranteed JSON output
        // NOTE: Gemini 3 uses "thinking" tokens (~250) so we need extra headroom
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": systemPrompt + "\n\n" + prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.1,
                "maxOutputTokens": 1024,  // Increased: Gemini 3 needs ~250 for thinking + output
                "responseMimeType": "application/json",
                "responseSchema": jsonSchema
            ]
        ]

        let requestData = try JSONSerialization.data(withJSONObject: requestBody)
        request.httpBody = requestData

        // Debug: log request
        if let requestStr = String(data: requestData, encoding: .utf8) {
            print("📤 Request body: \(requestStr.prefix(500))...")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VisualCoachError.invalidResponse
        }

        // Debug: log raw response
        if let rawResponse = String(data: data, encoding: .utf8) {
            print("📥 Raw API response: \(rawResponse.prefix(500))...")
        }

        if httpResponse.statusCode != 200 {
            // Try to extract error message
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw VisualCoachError.apiError(statusCode: httpResponse.statusCode, message: message)
            }
            throw VisualCoachError.apiError(statusCode: httpResponse.statusCode, message: "Unknown error")
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ Failed to parse API response as JSON")
            throw VisualCoachError.parseError
        }

        // Debug: log full response structure on error
        guard let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            print("❌ Response structure: \(json)")
            if let promptFeedback = json["promptFeedback"] as? [String: Any] {
                print("⚠️ Prompt feedback: \(promptFeedback)")
            }
            throw VisualCoachError.parseError
        }

        // Gemini 3 with responseMimeType=application/json should return pure JSON
        // But may include "thinking" parts - extract the actual JSON content
        var jsonText: String? = nil

        for part in parts {
            if let text = part["text"] as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                // With responseSchema, Gemini 3 returns raw JSON (no markdown backticks)
                if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
                    jsonText = trimmed
                    break
                }
                // Also check if it contains our schema keys (might have extra whitespace)
                if trimmed.contains("recommendedHeadsail") && trimmed.contains("{") {
                    jsonText = trimmed
                    break
                }
            }
        }

        // If still no JSON found, try first text part
        if jsonText == nil, let firstPart = parts.first, let text = firstPart["text"] as? String {
            jsonText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let result = jsonText else {
            print("❌ No text found in response parts: \(parts)")
            throw VisualCoachError.parseError
        }

        return result
    }

    // MARK: - Response Parsing

    private func parseRecommendations(from jsonString: String) throws -> CoachRecommendations {
        // Clean up the response - remove any markdown code blocks if present
        var cleanJson = jsonString
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract JSON object from response - find content between { and }
        if let startIndex = cleanJson.firstIndex(of: "{"),
           let endIndex = cleanJson.lastIndex(of: "}") {
            cleanJson = String(cleanJson[startIndex...endIndex])
        } else {
            print("❌ No JSON object found in response")
            throw VisualCoachError.parseError
        }

        guard let jsonData = cleanJson.data(using: .utf8) else {
            throw VisualCoachError.parseError
        }

        let decoder = JSONDecoder()
        do {
            let recommendations = try decoder.decode(CoachRecommendations.self, from: jsonData)
            return recommendations
        } catch {
            print("❌ JSON decode error: \(error)")
            print("❌ Extracted JSON: \(cleanJson)")
            throw VisualCoachError.parseError
        }
    }
}

// MARK: - Errors

enum VisualCoachError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parseError
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from API"
        case .apiError(let code, let message):
            return "API Error (\(code)): \(message)"
        case .parseError:
            return "Failed to parse recommendations"
        case .notConfigured:
            return "Visual coach not configured"
        }
    }
}

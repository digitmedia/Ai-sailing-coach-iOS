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
    @Published var isActive: Bool = false
    @Published var lastError: String?
    @Published var isLoading: Bool = false

    // MARK: - Configuration

    private let model = "gemini-3-flash-preview"
    private let updateInterval: TimeInterval = 10.0  // Update every 10 seconds
    private var apiKey: String?
    private var updateTimer: Timer?

    // Callback to get fresh sailing data
    var getSailingData: (() -> SailingData)?

    // MARK: - System Prompt

    private let systemPrompt = """
    You are an expert racing sailing coach analyzing real-time boat telemetry.
    Based on the sailing data provided, give concise recommendations for:
    1. Headsail selection (genoa for upwind TWA<50°, code0 for reaching 50-90°, gennaker for downwind >90°)
    2. Steering action (steady if optimal, headUp to point higher, bearAway to gain speed)
    3. Sail trim action (hold if optimal, sheetIn for more power, ease to reduce heel/drag)

    Decision guidelines:
    - Performance >= 90%: boat is doing well, recommend steady/hold unless angle needs adjustment
    - Performance 75-90%: minor adjustments needed
    - Performance < 75%: significant changes needed, usually bearAway + ease to build speed first

    Respond ONLY with a valid JSON object, no markdown, no explanation:
    {"recommendedHeadsail":"genoa","steeringRecommendation":"steady","sailTrimRecommendation":"hold"}

    Valid values:
    - recommendedHeadsail: "genoa", "code0", "gennaker"
    - steeringRecommendation: "steady", "headUp", "bearAway"
    - sailTrimRecommendation: "hold", "sheetIn", "ease"
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

        do {
            let response = try await callGemini3API(prompt: dataPrompt, apiKey: apiKey)
            let newRecommendations = try parseRecommendations(from: response)

            self.recommendations = newRecommendations
            self.lastError = nil
            print("✅ Visual coach recommendations updated: \(newRecommendations)")

        } catch {
            print("❌ Visual coach error: \(error.localizedDescription)")
            self.lastError = error.localizedDescription

            // Use fallback recommendations
            let fallback = CoachRecommendations.calculateFallback(from: sailingData)
            self.recommendations = fallback
            print("⚠️ Using fallback recommendations: \(fallback)")
        }

        isLoading = false
    }

    private func buildDataPrompt(from data: SailingData) -> String {
        """
        Current sailing telemetry:
        - Boat speed: \(String(format: "%.1f", data.boatSpeed)) knots
        - Target speed: \(String(format: "%.1f", data.targetSpeed)) knots
        - Performance: \(data.performance)%
        - True wind angle (TWA): \(Int(data.trueWindAngle))°
        - True wind speed (TWS): \(String(format: "%.1f", data.trueWindSpeed)) knots
        - Apparent wind angle (AWA): \(Int(data.apparentWindAngle))°
        - Course over ground (COG): \(Int(data.courseOverGround))°
        - Point of sail: \(data.pointOfSail.rawValue)

        Provide your JSON recommendations:
        """
    }

    // MARK: - Gemini 3 Flash API

    private func callGemini3API(prompt: String, apiKey: String) async throws -> String {
        // Use generateContent endpoint with JSON response mode
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"

        guard let url = URL(string: urlString) else {
            throw VisualCoachError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15 // 15 second timeout

        // Request body with minimal thinking for lowest latency
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
                "temperature": 0.3,
                "maxOutputTokens": 150,
                "responseMimeType": "application/json"
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VisualCoachError.invalidResponse
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
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw VisualCoachError.parseError
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Response Parsing

    private func parseRecommendations(from jsonString: String) throws -> CoachRecommendations {
        // Clean up the response - remove any markdown code blocks if present
        var cleanJson = jsonString
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleanJson.data(using: .utf8) else {
            throw VisualCoachError.parseError
        }

        let decoder = JSONDecoder()
        do {
            let recommendations = try decoder.decode(CoachRecommendations.self, from: jsonData)
            return recommendations
        } catch {
            print("❌ JSON decode error: \(error)")
            print("❌ Raw JSON: \(cleanJson)")
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

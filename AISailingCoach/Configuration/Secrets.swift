//
//  Secrets.swift
//  AISailingCoach
//
//  Configuration for API keys and sensitive data
//  In production, use environment variables or a secure key management system
//

import Foundation

/// Configuration for external API services
enum APIConfiguration {
    // MARK: - Gemini AI

    /// Gemini API Key - Set via Settings or environment variable
    static var geminiAPIKey: String {
        // Try environment variable first (for CI/CD)
        if let envKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !envKey.isEmpty {
            return envKey
        }

        // Fall back to UserDefaults (set via Settings UI)
        if let storedKey = UserDefaults.standard.string(forKey: "GeminiAPIKey"), !storedKey.isEmpty {
            return storedKey
        }

        // Return empty - will prompt user to enter key
        return ""
    }

    /// Check if Gemini is configured
    static var isGeminiConfigured: Bool {
        !geminiAPIKey.isEmpty
    }

    // MARK: - Signal K Server

    /// Default Signal K server URL for local network
    static let defaultSignalKURL = "ws://localhost:3000/signalk/v1/stream"

    /// Signal K server URL - can be overridden in settings
    static var signalKServerURL: String {
        UserDefaults.standard.string(forKey: "SignalKServerURL") ?? defaultSignalKURL
    }

    // MARK: - Feature Flags

    /// Enable Apple Foundation Models (when available)
    static let enableAppleFoundationModels = false

    /// Enable advanced tactical features
    static let enableTacticalFeatures = false

    /// Enable race timer
    static let enableRaceTimer = true
}

// MARK: - UserDefaults Keys

extension UserDefaults {
    enum Keys {
        static let geminiAPIKey = "GeminiAPIKey"
        static let signalKServerURL = "SignalKServerURL"
        static let selectedScenario = "SelectedScenario"
        static let highContrastMode = "HighContrastMode"
        static let nightMode = "NightMode"
        static let updateRate = "UpdateRate"
    }
}

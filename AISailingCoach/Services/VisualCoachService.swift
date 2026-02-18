//
//  VisualCoachService.swift
//  AISailingCoach
//
//  Protocol and provider enum for visual coach AI providers.
//  Implemented by Gemini3VisualCoachService and AppleFoundationCoachService.
//

import Foundation
import Combine

// MARK: - Provider Enum

/// Identifies which AI provider drives the visual coach instruction panes.
enum VisualCoachProvider: String, CaseIterable {
    case gemini = "gemini"
    case apple  = "apple"
}

// MARK: - Protocol

/// Common interface for visual coach providers.
/// Both Gemini 3 Flash (cloud) and Apple Foundation Models (on-device) conform to this.
/// All methods are expected to be called on the main actor.
protocol VisualCoachService: AnyObject {
    /// Latest recommendations, nil until first successful response.
    var recommendations: CoachRecommendations? { get }

    /// Combine publisher for recommendations — subscribe once, re-emit on each update.
    var recommendationsPublisher: AnyPublisher<CoachRecommendations?, Never> { get }

    /// Whether the service is actively polling / inferring.
    var isActive: Bool { get }

    /// Most recent error description; nil when last fetch succeeded.
    var lastError: String? { get }

    /// Whether a fetch is currently in progress.
    var isLoading: Bool { get }

    /// Closure called before each fetch to obtain the latest sailing data.
    var getSailingData: (() -> SailingData)? { get set }

    /// Start periodic polling / inference.
    func start()

    /// Stop polling / inference. Safe to call when already stopped.
    func stop()
}

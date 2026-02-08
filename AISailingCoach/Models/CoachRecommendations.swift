//
//  CoachRecommendations.swift
//  AISailingCoach
//
//  Data model for Gemini 3 Visual Coach recommendations
//  Represents the AI's instructions for each of the 4 UI panes
//

import Foundation

/// Recommendations from Gemini 3 Visual Coach for the 4 instruction panes
struct CoachRecommendations: Codable, Equatable {
    let recommendedHeadsail: HeadsailRecommendation
    let steeringRecommendation: SteeringRecommendation
    let sailTrimRecommendation: SailTrimRecommendation

    /// Default safe recommendations (used as fallback)
    static let defaults = CoachRecommendations(
        recommendedHeadsail: .genoa,
        steeringRecommendation: .steady,
        sailTrimRecommendation: .hold
    )
}

// MARK: - Headsail Recommendation

enum HeadsailRecommendation: String, Codable, CaseIterable {
    case genoa = "genoa"
    case code0 = "code0"
    case gennaker = "gennaker"

    /// Convert to UI type
    var asHeadsailType: HeadsailType {
        switch self {
        case .genoa: return .genoa
        case .code0: return .code0
        case .gennaker: return .gennaker
        }
    }

    /// Calculate recommendation based on true wind angle
    static func fromWindAngle(_ twa: Double) -> HeadsailRecommendation {
        let absTWA = abs(twa)
        if absTWA < 50 {
            return .genoa
        } else if absTWA < 90 {
            return .code0
        } else {
            return .gennaker
        }
    }
}

// MARK: - Steering Recommendation

enum SteeringRecommendation: String, Codable, CaseIterable {
    case steady = "steady"
    case headUp = "headUp"
    case bearAway = "bearAway"

    /// Convert to UI type
    var asSteeringAction: SteeringAction {
        switch self {
        case .steady: return .steady
        case .headUp: return .headUp
        case .bearAway: return .bearAway
        }
    }
}

// MARK: - Sail Trim Recommendation

enum SailTrimRecommendation: String, Codable, CaseIterable {
    case hold = "hold"
    case sheetIn = "sheetIn"
    case ease = "ease"

    /// Convert to UI type
    var asSailTrimAction: SailTrimAction {
        switch self {
        case .hold: return .hold
        case .sheetIn: return .sheetIn
        case .ease: return .ease
        }
    }
}

// MARK: - Fallback Calculator

extension CoachRecommendations {
    /// Calculate recommendations locally when API is unavailable
    static func calculateFallback(from data: SailingData) -> CoachRecommendations {
        // Headsail based on TWA
        let headsail = HeadsailRecommendation.fromWindAngle(data.trueWindAngle)

        // Steering based on performance and point of sail
        // More aggressive thresholds to match voice coach recommendations
        let steering: SteeringRecommendation
        let absTWA = abs(data.trueWindAngle)

        if data.performance >= 98 {
            // Nearly perfect - hold course
            steering = .steady
        } else if data.performance >= 93 {
            // Very good but could improve - slight adjustment upwind
            if absTWA < 50 {
                steering = .bearAway  // Bear away to build speed upwind
            } else {
                steering = .steady
            }
        } else {
            // Below 93% - bear away to build speed
            steering = .bearAway
        }

        // Trim based on performance
        // More aggressive to match voice coach recommendations
        let trim: SailTrimRecommendation
        if data.performance >= 98 {
            trim = .hold
        } else if data.performance >= 93 {
            // Slightly below optimal
            if absTWA < 50 {
                trim = .sheetIn  // More power upwind
            } else {
                trim = .ease     // Ease for speed on other points
            }
        } else {
            // Below 93% - ease to build speed
            trim = .ease
        }

        return CoachRecommendations(
            recommendedHeadsail: headsail,
            steeringRecommendation: steering,
            sailTrimRecommendation: trim
        )
    }
}

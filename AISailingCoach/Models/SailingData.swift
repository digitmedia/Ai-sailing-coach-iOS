//
//  SailingData.swift
//  AISailingCoach
//
//  Core sailing data model representing real-time boat telemetry
//

import Foundation

/// Core sailing telemetry data structure
struct SailingData: Codable, Equatable {
    // MARK: - Navigation Data

    /// Course Over Ground in degrees (0-360)
    var courseOverGround: Double

    /// Speed Over Ground in knots
    var speedOverGround: Double

    /// Boat speed through water in knots (from paddlewheel/GPS)
    var boatSpeed: Double

    // MARK: - Wind Data

    /// True Wind Speed in knots
    var trueWindSpeed: Double

    /// True Wind Angle in degrees relative to boat heading (-180 to 180, or 0-360)
    var trueWindAngle: Double

    /// Apparent Wind Speed in knots
    var apparentWindSpeed: Double

    /// Apparent Wind Angle in degrees relative to boat heading
    var apparentWindAngle: Double

    /// True Wind Direction in degrees (compass direction wind is coming FROM)
    var trueWindDirection: Double

    // MARK: - Performance Data

    /// Target boat speed from polar data for current TWA/TWS
    var targetSpeed: Double

    /// Performance percentage (boatSpeed / targetSpeed * 100)
    var performance: Int {
        guard targetSpeed > 0 else { return 0 }
        return Int(round((boatSpeed / targetSpeed) * 100))
    }

    // MARK: - Timestamps

    /// Timestamp of this data sample
    var timestamp: Date

    // MARK: - Initialization

    init(
        courseOverGround: Double = 0,
        speedOverGround: Double = 0,
        boatSpeed: Double = 0,
        trueWindSpeed: Double = 0,
        trueWindAngle: Double = 0,
        apparentWindSpeed: Double = 0,
        apparentWindAngle: Double = 0,
        trueWindDirection: Double = 0,
        targetSpeed: Double = 0,
        timestamp: Date = Date()
    ) {
        self.courseOverGround = courseOverGround
        self.speedOverGround = speedOverGround
        self.boatSpeed = boatSpeed
        self.trueWindSpeed = trueWindSpeed
        self.trueWindAngle = trueWindAngle
        self.apparentWindSpeed = apparentWindSpeed
        self.apparentWindAngle = apparentWindAngle
        self.trueWindDirection = trueWindDirection
        self.targetSpeed = targetSpeed
        self.timestamp = timestamp
    }
}

// MARK: - Sample Data for Development

extension SailingData {
    /// Upwind sailing scenario - good performance
    static var upwindSample: SailingData {
        SailingData(
            courseOverGround: 45,
            speedOverGround: 6.5,
            boatSpeed: 6.8,
            trueWindSpeed: 12.5,
            trueWindAngle: 42,
            apparentWindSpeed: 15.2,
            apparentWindAngle: 35,
            trueWindDirection: 0,
            targetSpeed: 7.5,
            timestamp: Date()
        )
    }

    /// Downwind sailing scenario - lower performance
    static var downwindSample: SailingData {
        SailingData(
            courseOverGround: 135,
            speedOverGround: 5.0,
            boatSpeed: 5.2,
            trueWindSpeed: 8.0,
            trueWindAngle: 150,
            apparentWindSpeed: 4.5,
            apparentWindAngle: 125,
            trueWindDirection: 345,
            targetSpeed: 7.0,
            timestamp: Date()
        )
    }

    /// Reaching scenario - excellent performance
    static var reachingSample: SailingData {
        SailingData(
            courseOverGround: 90,
            speedOverGround: 8.2,
            boatSpeed: 8.5,
            trueWindSpeed: 15.0,
            trueWindAngle: 90,
            apparentWindSpeed: 18.0,
            apparentWindAngle: 75,
            trueWindDirection: 0,
            targetSpeed: 8.2,
            timestamp: Date()
        )
    }

    /// Zero/stopped state
    static var empty: SailingData {
        SailingData()
    }
}

// MARK: - Sailing Point of Sail

enum PointOfSail: String, CaseIterable {
    case inIrons = "In Irons"
    case closeHauled = "Close Hauled"
    case closeReach = "Close Reach"
    case beamReach = "Beam Reach"
    case broadReach = "Broad Reach"
    case running = "Running"

    /// Determine point of sail from true wind angle
    static func from(trueWindAngle: Double) -> PointOfSail {
        let absAngle = abs(trueWindAngle)
        switch absAngle {
        case 0..<30:
            return .inIrons
        case 30..<60:
            return .closeHauled
        case 60..<80:
            return .closeReach
        case 80..<100:
            return .beamReach
        case 100..<150:
            return .broadReach
        default:
            return .running
        }
    }
}

extension SailingData {
    var pointOfSail: PointOfSail {
        PointOfSail.from(trueWindAngle: trueWindAngle)
    }
}

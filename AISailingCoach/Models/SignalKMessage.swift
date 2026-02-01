//
//  SignalKMessage.swift
//  AISailingCoach
//
//  Signal K protocol message structures for boat telemetry
//  Signal K is an open data format for marine use
//  https://signalk.org/specification/
//

import Foundation

// MARK: - Signal K Delta Message

/// Signal K delta message format for real-time updates
struct SignalKDelta: Codable {
    let context: String
    let updates: [SignalKUpdate]
}

struct SignalKUpdate: Codable {
    let source: SignalKSource?
    let timestamp: String?
    let values: [SignalKValue]
}

struct SignalKSource: Codable {
    let label: String?
    let type: String?
    let talker: String?  // NMEA talker ID
}

struct SignalKValue: Codable {
    let path: String
    let value: SignalKValueType
}

/// Signal K values can be different types
enum SignalKValueType: Codable {
    case double(Double)
    case string(String)
    case object([String: Double])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let objectValue = try? container.decode([String: Double].self) {
            self = .object(objectValue)
        } else {
            throw DecodingError.typeMismatch(
                SignalKValueType.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown value type")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    var doubleValue: Double? {
        if case .double(let value) = self {
            return value
        }
        return nil
    }
}

// MARK: - Signal K Paths

/// Standard Signal K paths for navigation and environment data
enum SignalKPath {
    // Navigation
    static let courseOverGroundTrue = "navigation.courseOverGroundTrue"
    static let speedOverGround = "navigation.speedOverGround"
    static let speedThroughWater = "navigation.speedThroughWater"
    static let headingTrue = "navigation.headingTrue"
    static let headingMagnetic = "navigation.headingMagnetic"

    // Environment - Wind
    static let windSpeedTrue = "environment.wind.speedTrue"
    static let windAngleTrue = "environment.wind.angleTrueWater"
    static let windSpeedApparent = "environment.wind.speedApparent"
    static let windAngleApparent = "environment.wind.angleApparent"
    static let windDirectionTrue = "environment.wind.directionTrue"

    // Performance
    static let polarSpeed = "performance.polarSpeed"
    static let polarSpeedRatio = "performance.polarSpeedRatio"
    static let velocityMadeGood = "performance.velocityMadeGood"
    static let targetAngle = "performance.targetAngle"
}

// MARK: - Signal K Parser

class SignalKParser {

    /// Parse a Signal K delta message and extract sailing data
    static func parse(delta: SignalKDelta, into existingData: SailingData) -> SailingData {
        var data = existingData

        for update in delta.updates {
            for value in update.values {
                guard let doubleValue = value.value.doubleValue else { continue }

                switch value.path {
                // Navigation
                case SignalKPath.courseOverGroundTrue:
                    // Signal K uses radians, convert to degrees
                    data.courseOverGround = radiansToDegrees(doubleValue)

                case SignalKPath.speedOverGround:
                    // Signal K uses m/s, convert to knots
                    data.speedOverGround = metersPerSecondToKnots(doubleValue)

                case SignalKPath.speedThroughWater:
                    data.boatSpeed = metersPerSecondToKnots(doubleValue)

                // Wind
                case SignalKPath.windSpeedTrue:
                    data.trueWindSpeed = metersPerSecondToKnots(doubleValue)

                case SignalKPath.windAngleTrue:
                    data.trueWindAngle = radiansToDegrees(doubleValue)

                case SignalKPath.windSpeedApparent:
                    data.apparentWindSpeed = metersPerSecondToKnots(doubleValue)

                case SignalKPath.windAngleApparent:
                    data.apparentWindAngle = radiansToDegrees(doubleValue)

                case SignalKPath.windDirectionTrue:
                    data.trueWindDirection = radiansToDegrees(doubleValue)

                // Performance
                case SignalKPath.polarSpeed:
                    data.targetSpeed = metersPerSecondToKnots(doubleValue)

                default:
                    break
                }
            }
        }

        data.timestamp = Date()
        return data
    }

    /// Parse JSON string to Signal K delta
    static func parse(json: String) -> SignalKDelta? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SignalKDelta.self, from: data)
    }

    /// Parse JSON data to Signal K delta
    static func parse(data: Data) -> SignalKDelta? {
        try? JSONDecoder().decode(SignalKDelta.self, from: data)
    }

    // MARK: - Unit Conversions

    private static func radiansToDegrees(_ radians: Double) -> Double {
        radians * 180.0 / .pi
    }

    private static func metersPerSecondToKnots(_ mps: Double) -> Double {
        mps * 1.94384
    }
}

// MARK: - Signal K Message Builder

class SignalKMessageBuilder {

    /// Build a Signal K delta message from sailing data
    static func build(from data: SailingData) -> SignalKDelta {
        let values: [SignalKValue] = [
            SignalKValue(
                path: SignalKPath.courseOverGroundTrue,
                value: .double(degreesToRadians(data.courseOverGround))
            ),
            SignalKValue(
                path: SignalKPath.speedOverGround,
                value: .double(knotsToMetersPerSecond(data.speedOverGround))
            ),
            SignalKValue(
                path: SignalKPath.speedThroughWater,
                value: .double(knotsToMetersPerSecond(data.boatSpeed))
            ),
            SignalKValue(
                path: SignalKPath.windSpeedTrue,
                value: .double(knotsToMetersPerSecond(data.trueWindSpeed))
            ),
            SignalKValue(
                path: SignalKPath.windAngleTrue,
                value: .double(degreesToRadians(data.trueWindAngle))
            ),
            SignalKValue(
                path: SignalKPath.windSpeedApparent,
                value: .double(knotsToMetersPerSecond(data.apparentWindSpeed))
            ),
            SignalKValue(
                path: SignalKPath.windAngleApparent,
                value: .double(degreesToRadians(data.apparentWindAngle))
            ),
            SignalKValue(
                path: SignalKPath.polarSpeed,
                value: .double(knotsToMetersPerSecond(data.targetSpeed))
            )
        ]

        let update = SignalKUpdate(
            source: SignalKSource(label: "AISailingCoach", type: "simulator", talker: nil),
            timestamp: ISO8601DateFormatter().string(from: data.timestamp),
            values: values
        )

        return SignalKDelta(context: "vessels.self", updates: [update])
    }

    private static func degreesToRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180.0
    }

    private static func knotsToMetersPerSecond(_ knots: Double) -> Double {
        knots / 1.94384
    }
}

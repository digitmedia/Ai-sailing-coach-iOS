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
    let context: String?  // Optional - not all messages have context
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
    let src: String?     // Alternative source identifier
    let pgn: Int?        // NMEA 2000 PGN
    let sentence: String? // NMEA 0183 sentence type

    // Regular initializer for creating instances directly
    init(label: String? = nil, type: String? = nil, talker: String? = nil,
         src: String? = nil, pgn: Int? = nil, sentence: String? = nil) {
        self.label = label
        self.type = type
        self.talker = talker
        self.src = src
        self.pgn = pgn
        self.sentence = sentence
    }

    // Allow unknown keys to be ignored when decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        talker = try container.decodeIfPresent(String.self, forKey: .talker)
        src = try container.decodeIfPresent(String.self, forKey: .src)
        pgn = try container.decodeIfPresent(Int.self, forKey: .pgn)
        sentence = try container.decodeIfPresent(String.self, forKey: .sentence)
    }

    private enum CodingKeys: String, CodingKey {
        case label, type, talker, src, pgn, sentence
    }
}

struct SignalKValue: Codable {
    let path: String
    let value: SignalKValueType
}

/// Signal K values can be different types
enum SignalKValueType: Codable {
    case double(Double)
    case int(Int)
    case string(String)
    case bool(Bool)
    case null
    case object([String: Double])
    case anyObject  // For complex objects we don't need to parse

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try decoding in order of likelihood
        if container.decodeNil() {
            self = .null
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let objectValue = try? container.decode([String: Double].self) {
            self = .object(objectValue)
        } else {
            // Accept any other object type without failing
            self = .anyObject
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .double(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        case .object(let value):
            try container.encode(value)
        case .anyObject:
            try container.encodeNil()
        }
    }

    var doubleValue: Double? {
        switch self {
        case .double(let value):
            return value
        case .int(let value):
            return Double(value)
        default:
            return nil
        }
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

    private static var loggedPaths = Set<String>()

    /// Parse a Signal K delta message and extract sailing data
    static func parse(delta: SignalKDelta, into existingData: SailingData) -> SailingData {
        var data = existingData
        var serverProvidedPolarSpeed = false

        for update in delta.updates {
            for value in update.values {
                let path = value.path

                // Log new paths we haven't seen before (for debugging)
                if !loggedPaths.contains(path) {
                    loggedPaths.insert(path)
                    print("📍 SignalK path discovered: \(path) = \(value.value)")
                }

                guard let doubleValue = value.value.doubleValue else { continue }

                // Handle various path formats (with and without prefixes)
                switch path {
                // Navigation - COG
                case SignalKPath.courseOverGroundTrue,
                     "navigation.courseOverGroundTrue",
                     "courseOverGroundTrue":
                    data.courseOverGround = radiansToDegrees(doubleValue)

                // Navigation - SOG
                case SignalKPath.speedOverGround,
                     "navigation.speedOverGround",
                     "speedOverGround":
                    data.speedOverGround = metersPerSecondToKnots(doubleValue)

                // Navigation - Boat Speed (STW)
                case SignalKPath.speedThroughWater,
                     "navigation.speedThroughWater",
                     "speedThroughWater":
                    data.boatSpeed = metersPerSecondToKnots(doubleValue)

                // Wind - True Wind Speed
                case SignalKPath.windSpeedTrue,
                     "environment.wind.speedTrue",
                     "wind.speedTrue":
                    data.trueWindSpeed = metersPerSecondToKnots(doubleValue)

                // Wind - True Wind Angle
                case SignalKPath.windAngleTrue,
                     "environment.wind.angleTrueWater",
                     "environment.wind.angleTrueGround",
                     "wind.angleTrueWater":
                    data.trueWindAngle = radiansToDegrees(doubleValue)

                // Wind - Apparent Wind Speed
                case SignalKPath.windSpeedApparent,
                     "environment.wind.speedApparent",
                     "wind.speedApparent":
                    data.apparentWindSpeed = metersPerSecondToKnots(doubleValue)

                // Wind - Apparent Wind Angle
                case SignalKPath.windAngleApparent,
                     "environment.wind.angleApparent",
                     "wind.angleApparent":
                    data.apparentWindAngle = radiansToDegrees(doubleValue)

                // Wind - True Wind Direction
                case SignalKPath.windDirectionTrue,
                     "environment.wind.directionTrue",
                     "wind.directionTrue":
                    data.trueWindDirection = radiansToDegrees(doubleValue)

                // Performance - Target/Polar Speed
                case SignalKPath.polarSpeed,
                     "performance.polarSpeed",
                     "performance.targetSpeed":
                    data.targetSpeed = metersPerSecondToKnots(doubleValue)
                    serverProvidedPolarSpeed = true

                default:
                    break
                }
            }
        }

        // Calculate true wind from apparent wind for consistency
        // The server sends TWA and AWA from different time slices, so they don't match up
        // Use proper vector math to ensure TWS/TWA are consistent with AWS/AWA
        if data.boatSpeed > 0 && data.apparentWindSpeed > 0 {
            let (calculatedTWS, calculatedTWA) = calculateTrueWind(
                aws: data.apparentWindSpeed,
                awa: data.apparentWindAngle,
                boatSpeed: data.boatSpeed
            )
            data.trueWindSpeed = calculatedTWS
            data.trueWindAngle = calculatedTWA
        }

        // If target speed wasn't provided by the server, estimate it from TWS and TWA
        // Always recalculate since TWS/TWA change continuously
        if !serverProvidedPolarSpeed && data.trueWindSpeed > 0 {
            data.targetSpeed = estimateTargetSpeed(tws: data.trueWindSpeed, twa: abs(data.trueWindAngle))
        }

        data.timestamp = Date()
        return data
    }

    /// Calculate true wind speed and angle from apparent wind using vector math
    /// This ensures TWS/TWA are always consistent with AWS/AWA
    private static func calculateTrueWind(aws: Double, awa: Double, boatSpeed: Double) -> (tws: Double, twa: Double) {
        // Convert AWA to radians for trig functions
        let awaRad = awa * .pi / 180.0

        // True wind components (relative to boat heading)
        // AWS vector - Boat speed vector = TWS vector
        let twsX = aws * cos(awaRad) - boatSpeed  // Forward component
        let twsY = aws * sin(awaRad)               // Sideways component

        // Calculate TWS (magnitude of true wind vector)
        let tws = sqrt(twsX * twsX + twsY * twsY)

        // Calculate TWA (angle of true wind vector)
        var twa = atan2(twsY, twsX) * 180.0 / .pi

        // Ensure TWA is positive (0-180 for starboard tack, or keep sign for port/starboard indication)
        // Signal K convention: positive = starboard, negative = port
        // Keep the sign from the original AWA to maintain port/starboard indication
        if awa < 0 {
            twa = -abs(twa)
        } else {
            twa = abs(twa)
        }

        return (tws, twa)
    }

    /// Estimate target boat speed based on TWS and TWA using simplified polar data
    /// Based on a typical 35-40ft racing keelboat (e.g. J/109, First 40, etc.)
    private static func estimateTargetSpeed(tws: Double, twa: Double) -> Double {
        // Realistic polar ratios (boat speed / true wind speed) for a displacement keelboat
        let polarRatio: Double

        switch twa {
        case 0..<30:
            // In irons / pinching - very slow
            polarRatio = 0.2
        case 30..<45:
            // Close hauled - typical keelboat: ~5.5-6.5 kts in 10 kts TWS
            polarRatio = 0.60
        case 45..<60:
            // Close reach - slightly faster
            polarRatio = 0.70
        case 60..<90:
            // Beam reach - fastest angle for displacement boat
            polarRatio = 0.80
        case 90..<120:
            // Broad reach with kite
            polarRatio = 0.75
        case 120..<150:
            // Deep broad reach with spinnaker
            polarRatio = 0.65
        case 150..<180:
            // Dead downwind - VMG angle would be better
            polarRatio = 0.55
        default:
            polarRatio = 0.4
        }

        // Calculate target speed, capped at reasonable maximum for a keelboat
        let targetSpeed = tws * polarRatio
        return min(targetSpeed, 10.0)  // Cap at 10 knots for displacement keelboat
    }

    /// Parse JSON string to Signal K delta
    static func parse(json: String) -> SignalKDelta? {
        guard let data = json.data(using: .utf8) else {
            print("❌ SignalKParser: Failed to convert JSON string to data")
            return nil
        }

        do {
            return try JSONDecoder().decode(SignalKDelta.self, from: data)
        } catch {
            // Only log parsing errors for delta messages (have "updates")
            if json.contains("\"updates\"") {
                print("❌ SignalKParser: Decode error: \(error)")
            }
            return nil
        }
    }

    /// Parse JSON data to Signal K delta
    static func parse(data: Data) -> SignalKDelta? {
        do {
            return try JSONDecoder().decode(SignalKDelta.self, from: data)
        } catch {
            print("❌ SignalKParser: Decode error: \(error)")
            return nil
        }
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
